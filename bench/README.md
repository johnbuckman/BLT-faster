# Benchmarks

Two Tcl scripts to measure BLT graph redraw speed on the real on-screen path.
Run them with a `wish` whose BLT has been patched by `../patches/blt-faster.patch`
(e.g. AndroWish / undroidwish, or any BLT 2.4 build).

* **`de1_faithful.tcl`** — a faithful replica of the Decent DE1 app's live
  espresso page: three stacked graphs (pressure/flow/temperature), the full
  element set + static profile-preview overlay, 10 Hz over a 45 s shot. This is
  the real-world workload the project was built for.

* **`blt_window.tcl`** — a smaller two-graph harness for isolating where the
  per-frame time goes (toggle ticks / grid / elements).

Both control the two options explicitly via environment variables so you can A/B
them regardless of the compiled-in default:

```sh
# stock behaviour (both off):
BB_CACHELABELS=0 BB_CHROME=0  wish de1_faithful.tcl
# label cache only (the win for auto-scaling live charts):
BB_CACHELABELS=1 BB_CHROME=0  wish de1_faithful.tcl
# chrome cache on a fixed-axis graph:
BB_CACHELABELS=1 BB_CHROME=1 BB_FIXEDX=1  wish de1_faithful.tcl
```

Useful `de1_faithful.tcl` knobs: `BB_FACTOR` (0.5 = 1280×800, 1.0 = 2560×1600),
`BB_FIXEDX` (1 = fixed x-axis), `BB_SCALE`, `BB_GOD`, `BB_HZ`, `BB_SECS`.

Each script prints its `ms/frame` result line to stdout **and** appends it to an
output file (default under `/tmp`) — GUI `wish` builds often swallow stdout, so
check the file if you see nothing. See `../docs/BENCHMARKS.md` for numbers.
