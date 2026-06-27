# Benchmarks

All numbers are wall-clock **milliseconds per on-screen redraw**, measured on an
Apple M4 with the AndroWish/undroidwish SDL2+AGG BLT backend. The relative
speedups typically hold or grow on slower hardware (tablets / SBCs), where text
rasterization is comparatively more expensive.

Measure the real path: append to the vectors, then `update idletasks`, and time
that. **Do not** use `$graph snap` to benchmark (it forces a full redraw + photo
read-back and bypasses `-bufferchrome`).

## Real-world workload: live espresso page

`bench/de1_faithful.tcl` is a faithful replica of the Decent DE1 app's Insight
espresso page: **three** stacked graphs (pressure / flow / temperature), the full
element set (live line, dashed goal line, thick god-shot comparison line, grey
state-change markers, and a static profile-preview overlay), fixed y-axes, and a
10 Hz loop that grows ~22 vectors over a 45 s "shot" — exactly like the app.

Knobs are environment variables; `BB_CACHELABELS` / `BB_CHROME` set the two
options explicitly (so you can A/B them regardless of the compiled-in default).

```
# stock (both off):
BB_CACHELABELS=0 BB_CHROME=0 wish bench/de1_faithful.tcl
# label cache only:
BB_CACHELABELS=1 BB_CHROME=0 wish bench/de1_faithful.tcl
```

### Continuously auto-scaling x-axis (the real live behaviour), 1280×800

| config                         | ms/frame | speedup |
|--------------------------------|----------|---------|
| stock                          | 5.3      | 1.0×    |
| `-cachelabels`                 | 3.9      | **1.34×** |
| `-bufferchrome` (alone)        | ~5.5     | ~0.95× (no help: axis moves every frame) |

`-cachelabels` is the win here, and it's pixel-identical.

### Fixed-axis graph (history view / dashboard / finished plot)

| config           | ms/frame | speedup |
|------------------|----------|---------|
| stock            | 3.8      | 1.0×    |
| `-bufferchrome`  | 2.0      | **1.9×** |

When the axes don't move, the chrome is cached and only the data redraws.

## Component breakdown

`bench/blt_window.tcl` renders a two-graph layout via the on-screen path and lets
you toggle ticks / grid / elements (`BB_TICKS`, `BB_GRID`, `BB_ELEMS`) to see
where the time goes. The headline finding: hiding the axis tick labels removed
the majority of the per-frame cost, while halving line widths / dropping elements
barely moved it — which is what motivated caching the chrome rather than tuning
the data drawing.

## Reproducing

1. Build a `wish` with BLT patched by `patches/blt-faster.patch` (e.g. AndroWish
   / undroidwish, or any BLT 2.4 build).
2. Run the scripts above with that `wish`. Each prints `ms/frame` to a file
   (default under `/tmp`) and to stdout.
3. Compare `BB_CACHELABELS=0 BB_CHROME=0` (stock behaviour) against the defaults.

Note: GUI `wish` builds often swallow stdout, so the scripts also write their
result line to a file — see the `set OUT` / `emit` lines at the top of each
script.
