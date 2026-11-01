# BLT-faster

A C patch for the **BLT `graph` / `stripchart` / `barchart`** widget that
reduces the per-frame cost of live, continuously-redrawn charts, with no change
to rendered output. Patches BLT 2.4 (as bundled in
[AndroWish](https://www.androwish.org/) / undroidwish, and most other BLT 2.4
trees).

Part of a collection of Tcl/Tk projects:
**<https://johnbuckman.github.io/tcltk/>** —
project page: **<https://johnbuckman.github.io/tcltk/blt-faster.html>**.

Two new graph options ship in the patch:

| option | default | what it does | speedup | visual change |
|--------|---------|--------------|---------|---------------|
| `-cachelabels`  | **on**  | caches rendered axis tick-label sprites and blits them instead of re-rasterizing the text every redraw | **~1.3×** on live charts | none — pixel-identical |
| `-bufferchrome` | **off** (opt-in) | caches the entire static "chrome" (axes, grid, tick labels, background, border) and redraws only the data lines on top | **~1.9×** on graphs whose axes don't move between frames | none |

`-cachelabels` is **on by default**: it is a pixel-identical change for any
graph — patch BLT, rebuild, and every graph's labels use the cache, no Tcl
changes needed.

`-bufferchrome` is **off by default** and opt-in (`-bufferchrome 1`), because its
effect depends on the graph: it helps when the axes are static or change rarely,
but on a graph whose x-axis auto-rescales on every frame (a live stripchart) it
cannot cache anything and is slightly slower. Enable it for the graphs that
suit it.

A third option — **redraw throttling** (`-redrawduty` / `-minredrawms`) — is
designed and documented but not yet part of the applied patch; see
[Redraw throttling](#redraw-throttling-designed) below.

## What it is

BLT graphs redraw for real-time data (espresso shots, oscilloscopes, sensor
dashboards). Redrawing one at 10–60 Hz is expensive. Profiling a case — three
live espresso charts in the [Decent DE1 app](https://decentespresso.com/)
running on AndroWish — showed the per-frame cost is **dominated by the axes, not
the data**:

* **~55–70 % of every frame** goes into drawing the axis tick **labels** and tick
  **marks** — re-rasterized through FreeType/AGG on *every* redraw, even though
  the labels ("0", "5", "10"…) rarely change.
* The data curves are a minority of the cost.
* Line width, point count, `-smooth`, `-reduce`, and dashes each move the frame
  time by **less than 10 %**.

The approach is to avoid repeating the axis work every frame:

* **`-cachelabels`** renders each unique tick-label string once into a small
  pixmap (on the axis-margin background, where there's no grid underneath) and
  *blits* it at the new position each frame. Pixel-identical, and it applies
  even when the axis is auto-scaling (the label *text* is reused; only its
  position moves).
* **`-bufferchrome`** renders the whole static chrome once into a cache pixmap
  and reuses it, drawing only the elements on top. It re-renders the chrome only
  when the axis range / tick set changes (tracked by a signature), so it helps
  graphs whose axes are fixed or change rarely (history views, dashboards,
  finished plots).

See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) for the diagnosis and
implementation, and [docs/BENCHMARKS.md](docs/BENCHMARKS.md) for numbers and how
to reproduce them.

## Measured speedups

Apple M4, the 3-chart live espresso page (pressure/flow/temperature), full
element set, 10 Hz over a 45 s "shot":

| chart kind | stock BLT | BLT-faster | speedup |
|------------|-----------|------------|---------|
| live charts, **auto-scaling** x-axis (1280×800) | 5.3 ms/frame | 3.9 ms/frame | **1.34×** (`-cachelabels`) |
| **fixed-axis** graph (history / zoomed / dashboard) | 3.8 ms/frame | 2.0 ms/frame | **1.9×** (`-bufferchrome`) |

The relative speedup typically grows on slower hardware (tablets, SBCs), where
text rasterization is comparatively more expensive than on a fast desktop.

When benchmarking, measure the **on-screen** redraw path (`update idletasks`),
not `$graph snap` — snap forces a full reset-world redraw plus a photo read-back
and bypasses `-bufferchrome`, so it doesn't reflect real live-redraw cost.

## Quick start

```sh
# from the root of a BLT 2.4 source tree (the directory containing src/)
patch -p1 < /path/to/BLT-faster/patches/blt-faster.patch
# ...then rebuild BLT the way you normally do.
```

Or use the helper:

```sh
./apply-patch.sh /path/to/blt
```

After rebuilding, every graph has `-cachelabels` **on**. To also cache the
chrome on a static-axis graph, opt in with `-bufferchrome 1`.

The patch touches four files (`src/bltGraph.{c,h}`, `src/bltGrAxis.{c,h}`), ~375
added lines, and is additive — with the options at their defaults the rendering
is identical to stock BLT. BLT loads as a runtime library, so a test script can
`load` the patched build to override an embedded one without relinking the host
wish.

## Application code changes

Not required for `-cachelabels`. Because it is on by default, every existing
`graph` / `stripchart` / `barchart` gets the label-cache change the moment it
runs on the patched BLT. No Tcl changes, no recompiling the app, nothing to opt
into. Confirmed on the Decent DE1 espresso UI, whose charts sped up with zero
application-side changes.

Application code changes are only needed to enable `-bufferchrome` on a
particular graph — that one is opt-in, so add `-bufferchrome 1` to that graph's
creation or `configure`.

## Turning the options on/off

Both are boolean graph options, settable at creation or via `configure`:

```tcl
.g configure -bufferchrome 1     ;# opt IN to the chrome cache (default off)
.g configure -cachelabels  0     ;# opt OUT of the label cache (default on)
```

`-cachelabels` is safe to leave on (pixel-identical, applies to any graph).
Turn `-bufferchrome` on for graphs whose axes are static or change rarely
(history views, dashboards, finished plots, fixed-range live charts) — that is
where the ~1.9× applies. Leave it off for a graph whose **x-axis auto-resizes on
every single frame**, where it cannot cache anything and adds one extra
full-window blit (roughly neutral-to-slightly-slower).

## Redraw throttling (designed)

Separate from the two shipping options, BLT-faster documents a redraw-pacing
pair that limits how often expensive redraws run on slow hardware:

* **`-redrawduty <k>`** — adaptive. After a redraw that took D ms, don't redraw
  again for D·k ms (k=1 ≈ 50 % duty cycle). Self-tuning.
* **`-minredrawms <ms>`** — a fixed minimum interval between redraws.

This is a **responsiveness / CPU-budget** change — it can free ~40 % CPU on a
slow tablet where stock BLT leaves only ~8 % headroom — rather than a
chart-freshness fix, and it composes with `-cachelabels` / `-bufferchrome`.
These options are designed and documented but not yet part of the applied patch.

## Correctness & compatibility

* **`-cachelabels` is verified pixel-identical** (snapshot comparison, zero
  differing pixels) and falls back to normal drawing for rotated / active /
  shadowed labels, and for a label whose position is outside the 16-bit X
  coordinate range. That happens before a graph's first layout; blitting there
  crashed AndroWish (SDL's blit clipping overflowed) and could misplace the
  label on X11.
* **`-bufferchrome`** reproduces a full redraw exactly on a cache *miss*, and on
  a cache *hit* the chrome is by definition unchanged. Its signature tracks
  graph geometry, focus, and each axis's range + tick counts, and it invalidates
  on graph/axis reconfigure. See
  [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) for the edge cases if you drive
  BLT in unusual ways.
* Targets **BLT 2.4**. Developed against the BLT in AndroWish / undroidwish
  (SDL2 + AGG backend), where the speedup is largest, but the changes use only
  standard BLT/Tk internals and should build on any BLT 2.4 tree.

## License

GPL-3.0. The patch and docs are the original work of John Buckman; they modify
BLT, which carries its own license — this repo distributes the changes, **not**
the BLT source.
