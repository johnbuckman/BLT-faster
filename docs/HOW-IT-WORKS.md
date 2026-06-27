# How BLT-faster works

## The diagnosis

Profiling a BLT `graph` redrawing live data (the real-world case: the three
stacked espresso charts in the Decent DE1 app on AndroWish, appending ~22 vectors
at 10 Hz and redrawing each frame) gave a counter-intuitive breakdown of where a
frame goes:

| component                              | share of frame |
|----------------------------------------|----------------|
| axis tick **labels** (text rasterized) | large          |
| axis tick **marks** + axis lines       | large          |
| the data curves themselves             | minority       |
| grid, background, buffer copies        | the rest       |

Together the **axes (labels + tick marks) are ~55–70 % of every frame**, and
they are redrawn from scratch every time even though, frame to frame, the axis
labels and grid barely change. Meanwhile the things people normally tune — line
width, number of points, `-smooth`, `-reduce`, dashes, symbol size — each change
the frame time by **under 10 %**. The data isn't the bottleneck; the chrome is.

Two important measurement notes:

* Measure the **on-screen redraw path** (modify a vector, then `update
  idletasks`). Do **not** use `$graph snap` to benchmark — `snap` forces a full
  `RESET_WORLD` redraw *and* a photo read-back, which both masks the real cost
  and bypasses the caches below.
* `snap` also bypasses `-bufferchrome` entirely (it goes through `Blt_DrawGraph`
  directly, not `DisplayGraph`), so a `snap` of a buffered graph is always a
  fresh full render.

## `-cachelabels` — cache the tick-label sprites

Axis tick labels are a tiny set of repeating strings ("0", "5", "10", …). They
sit in the axis **margin**, which is solid graph background — there is no grid or
data underneath them. So each label can be rendered **once** onto a small
background-filled pixmap and then **blitted** at the right position every frame,
instead of being re-rasterized through FreeType/AGG each time.

Implementation (`src/bltGrAxis.c`):

* A per-axis `Blt_HashTable labelCache` keyed by the label string. Each entry
  (`CachedLabel`) holds a pixmap of `background + text`, plus the text size.
* In `DrawAxis`, when `-cachelabels` is on and the label is "simple" (no
  rotation, not active/disabled/shadowed), we fetch-or-render the sprite via
  `GetLabelSprite` and `XCopyArea` it to `Blt_TranslateAnchor(...)` — the exact
  top-left the normal path would have drawn the text at. Otherwise we fall back
  to `Blt_DrawText`.
* The sprite background is filled with `graphPtr->fillGC` — the *same* GC that
  paints the margins — so compositing the sprite is pixel-identical to drawing
  the text directly on the margin.
* The cache is freed/invalidated on axis reconfigure (`ConfigureAxis`) and graph
  reconfigure (`Blt_ClearAllLabelCaches` from `ConfigureGraph`), and on axis
  destroy.

Because only the label's *position* changes when an axis auto-scales (the text
is the same), `-cachelabels` helps even moving-axis live charts. Verified
pixel-identical by snapshot comparison.

## `-bufferchrome` — cache the whole static chrome

`-bufferchrome` caches everything *except* the data overlay. On each redraw
(`DisplayGraph` → `DrawCachedChrome` in `src/bltGraph.c`):

1. Ensure a window-sized `chromePixmap` exists.
2. Compute `Blt_ComputeChromeSignature()` — a cheap FNV fold of the graph
   geometry (`width/height`, plot rect), focus state, and for every axis its
   `hidden`, `min`, `max`, and major/minor tick counts.
3. If the signature changed (or the cache is invalid), render the chrome into
   `chromePixmap` via `DrawChrome()` — background fill, grid, under-markers,
   under-legend, axis limits, margins (axes + tick labels), 3D border, focus
   ring. This is exactly `Blt_DrawGraph` minus the dynamic overlay, in the same
   order.
4. Blit `chromePixmap` onto the draw buffer, then draw only the dynamic overlay
   on top: `Blt_DrawElements`, above-markers, active elements, raised in-plot
   legend.

So when the axes don't move between frames the chrome is rendered **once** and
reused; only the data lines are redrawn. When the axis range or tick set
genuinely changes, the signature changes and the chrome is re-rendered (a normal
full frame). This is gated by the new graph option (default on); it is a fully
separate path from BLT's existing `-bufferelements`, which caches *elements +
chrome together* and is therefore invalidated on every data change.

### When it helps and when it doesn't

* **Fixed / rarely-changing axes** (history views, dashboards, finished plots,
  fixed-range live charts): big win (~1.9×), chrome cached almost always.
* **An x-axis that auto-resizes on every single frame** (tight auto-scale of a
  growing live series): the signature changes every frame → cache miss every
  frame → it re-renders the chrome anyway *plus* one extra full-window blit, so
  it's roughly neutral to ~15 % slower. Set `-bufferchrome 0` on such a graph,
  or give it a fixed/stepped axis so the chrome can be cached.

## Defaults & opting in/out

* `-cachelabels` defaults **on** (`DEF_GRAPH_CACHE_LABELS = "1"`, field `TRUE` in
  `CreateGraph`) — it's a free, pixel-identical win for any graph.
* `-bufferchrome` defaults **off** (`DEF_GRAPH_BUFFER_CHROME = "0"`, field
  `FALSE`) — opt in with `-bufferchrome 1` on the graphs that suit it (static /
  rarely-changing axes), since on a per-frame-rescaling axis it's a slight loss.

Both are ordinary boolean graph options, settable at creation or via `configure`
(`-cachelabels 0` to opt out of label caching, `-bufferchrome 1` to opt in to
chrome caching).

## Limitations

`-bufferchrome`'s signature + invalidation covers the common cases (data changes,
axis range/tick changes, geometry, focus, graph/axis reconfigure). Two edge
cases are **not** currently wired to invalidate the chrome cache mid-flight, so
if you rely on them with `-bufferchrome` on you may see stale chrome until the
next axis/graph reconfigure:

* adding or moving an **under-marker** (a marker drawn beneath the elements)
  while the cache is warm;
* reconfiguring the **grid** or **legend** while the cache is warm.

These don't occur in the typical "set the graph up, then stream data" usage. If
you hit one, either `configure` the axis/graph (which invalidates the cache) or
set `-bufferchrome 0` on that graph. `-cachelabels` has no such caveat.
