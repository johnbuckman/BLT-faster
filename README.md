# BLT-faster

Drop-in speedups for the **BLT `graph`/`stripchart`/`barchart`** widget that make
live, continuously-redrawn charts noticeably faster — with **no change to how the
chart looks**. Ships as a small C patch against BLT 2.4 (as bundled in
[AndroWish](https://www.androwish.org/) / undroidwish, and most other BLT 2.4
trees).

Two new graph options:

| option | default | what it does | speedup | visual change |
|--------|---------|--------------|---------|---------------|
| `-cachelabels`  | **on**  | caches rendered axis tick-label sprites and blits them instead of re-rasterizing the text every redraw | **~1.3×** on live charts | none — pixel-identical |
| `-bufferchrome` | **off** (opt-in) | caches the entire static "chrome" (axes, grid, tick labels, background, border) and redraws only the data lines on top | **~1.9×** on graphs whose axes don't move between frames | none |

`-cachelabels` is **on by default** because it's a free, pixel-identical win for
any graph — patch BLT, rebuild, and every graph's labels get cheaper, no Tcl
changes needed.

`-bufferchrome` is **off by default** and opt-in (`-bufferchrome 1`), because its
benefit depends on the graph: it's a big win when the axes are static or change
rarely, but on a graph whose x-axis auto-rescales on every frame (a classic
live stripchart) it can't cache anything and is slightly slower. Turn it on for
the graphs that suit it.

## Why this exists

BLT graphs are wonderful for real-time data (espresso shots, oscilloscopes,
sensor dashboards…), but redrawing one at 10–60 Hz can be surprisingly
expensive. Profiling a real-world case — the three live espresso charts in the
[Decent DE1 app](https://decentespresso.com/) running on AndroWish — showed the
per-frame cost is **dominated by the axes, not the data**:

* **~55–70 % of every frame** goes into drawing the axis tick **labels** and tick
  **marks** — re-rasterized through FreeType/AGG on *every* redraw, even though
  the labels ("0", "5", "10"…) rarely change.
* The actual data curves are a *minority* of the cost.
* The usual knobs people reach for — line width, point count, `-smooth`,
  `-reduce`, dashes — each move the frame time by **less than 10 %**. They're a
  dead end.

So the win is to stop re-doing the axis work every frame:

* **`-cachelabels`** renders each unique tick-label string once into a tiny
  pixmap (on the axis-margin background, where there's no grid underneath) and
  just *blits* it at the new position each frame. Pixel-identical, and it helps
  even when the axis is auto-scaling (the label *text* is reused; only its
  position moves).
* **`-bufferchrome`** goes further: it renders the whole static chrome once into
  a cache pixmap and reuses it, drawing only the elements on top. It re-renders
  the chrome only when the axis range / tick set actually changes (tracked by a
  cheap signature), so it's a big win for graphs whose axes are fixed or change
  rarely (history views, dashboards, finished plots).

See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) for the full diagnosis and
implementation, and [docs/BENCHMARKS.md](docs/BENCHMARKS.md) for numbers and how
to reproduce them.

## Measured speedups

Apple M4, the faithful 3-chart live espresso page (pressure/flow/temperature),
full element set, 10 Hz over a 45 s "shot":

| chart kind | stock BLT | BLT-faster | speedup |
|------------|-----------|------------|---------|
| live charts, **auto-scaling** x-axis (1280×800) | 5.3 ms/frame | 3.9 ms/frame | **1.34×** (`-cachelabels`) |
| **fixed-axis** graph (history / zoomed / dashboard) | 3.8 ms/frame | 2.0 ms/frame | **1.9×** (`-bufferchrome`) |

The relative win typically *grows* on slower hardware (tablets, SBCs), where
text rasterization is comparatively more expensive than on a fast desktop.

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

After rebuilding, every graph has `-cachelabels` **on** automatically. To also
cache the chrome on a static-axis graph, opt in with `-bufferchrome 1`.

The patch touches only four files (`src/bltGraph.{c,h}`, `src/bltGrAxis.{c,h}`),
~375 added lines, and is additive — with the options at their defaults the
rendering is identical to stock BLT, just faster.

## Turning the options on/off

Both are ordinary boolean graph options, settable at creation or via `configure`:

```tcl
.g configure -bufferchrome 1     ;# opt IN to the chrome cache (default off)
.g configure -cachelabels  0     ;# opt OUT of the label cache (default on)
```

`-cachelabels` is always safe to leave on (pixel-identical, helps any graph).
Turn `-bufferchrome` on for graphs whose axes are static or change rarely
(history views, dashboards, finished plots, fixed-range live charts) — that's
where the ~1.9× lives. Leave it off for a graph whose **x-axis auto-resizes on
every single frame**, where it can't cache anything useful and adds one extra
full-window blit (roughly neutral-to-slightly-slower).

## Correctness & compatibility

* **`-cachelabels` is verified pixel-identical** (snapshot comparison, zero
  differing pixels) and falls back to normal drawing for rotated / active /
  shadowed labels.
* **`-bufferchrome`** reproduces a full redraw exactly on a cache *miss*, and on
  a cache *hit* the chrome is by definition unchanged. Its signature tracks
  graph geometry, focus, and each axis's range + tick counts, and it invalidates
  on graph/axis reconfigure. See
  [docs/HOW-IT-WORKS.md#limitations](docs/HOW-IT-WORKS.md#limitations) for the
  edge cases (under-markers and grid/legend reconfigure mid-cache) if you drive
  BLT in unusual ways.
* Targets **BLT 2.4**. Developed against the BLT in AndroWish / undroidwish
  (SDL2 + AGG backend), which is where the win is largest, but the changes use
  only standard BLT/Tk internals and should build on any BLT 2.4 tree.

## License

GPL-3.0. The patch and docs are the original work of John Buckman; they modify
BLT, which carries its own (permissive) license — this repo distributes the
changes, **not** the BLT source.
