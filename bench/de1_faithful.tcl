#!/usr/bin/env wish
# Faithful replica of the de1app Insight-skin live espresso page: THREE stacked
# BLT graphs (pressure / flow / temperature), the exact element set, fixed
# y-axes + autoscaling x, a static profile-preview overlay, and a 10 Hz append
# loop that grows ~22 vectors per frame exactly like
# ::gui::update::append_live_data_to_espresso_chart.
#
# Knobs (env):
#   BB_CHROME  0/1   -bufferchrome (default 0)
#   BB_SCALE   0/1   bluetooth scale connected -> extra weight lines (default 1)
#   BB_FACTOR  rescale factor: 0.5 = 1280x800 tablet, 1.0 = 2560x1600 (default 0.5)
#   BB_GOD     0/1   overlay a "god shot" comparison (fills god_* lines) (default 0)
#   BB_FIXEDX  0/1   fix x-axis (rolling/zoomed view) vs autoscale (default 0)
#   BB_HZ      append rate (default 10)
#   BB_SECS    shot length seconds (default 45)
package require Tk
package require BLT
proc envd {k d} { return [expr {[info exists ::env($k)] ? $::env($k) : $d}] }
set CHROME [envd BB_CHROME 0]
set CLABELS [envd BB_CACHELABELS 0]
set SUBDIV0 [envd BB_SUBDIV 0]
set MINORG [envd BB_MINORGRID 1]
set SCALE  [envd BB_SCALE 1]
set F      [envd BB_FACTOR 0.5]
set GOD    [envd BB_GOD 0]
set FIXEDX [envd BB_FIXEDX 0]
set HZ     [envd BB_HZ 10]
set SECS   [envd BB_SECS 45]
# x-axis behaviour of the LIVE chart:
#   grow  = resize x-max to the newest data point EVERY frame (the real de1app)
#   step5 = resize x-max only when it crosses the next 5 s boundary
#   step10= ... next 10 s boundary
#   pin   = leave it to BLT autoscale (preview overlay tends to pin it)
set XMODE  [envd BB_XMODE grow]
set PREVIEW [envd BB_PREVIEW 1] ;# draw the static profile-preview overlay
set TICKS  [envd BB_TICKS 1]    ;# draw axis tick labels
set GODL   [envd BB_GODLINES 1] ;# create the (empty) god comparison line elements
set OUT [lindex $argv 0]; if {$OUT eq ""} { set OUT /tmp/de1_faithful.txt }
set ::fd [open $OUT a]; proc emit {m} { puts $::fd $m; flush $::fd; puts $m }

proc rx {n} { expr {int($n * $::F + 0.5)} }
proc ry {n} { expr {int($n * $::F + 0.5)} }
# Insight: charts_width 1990 (of 2560 ref), chart height 410 (of 1600 ref)
set CW [rx 1990]
set CH [ry 410]

# colors from Insight defaults
set pcol  #66B6FF ; # pressure
set pgod  #C0E0FF
set fcol  #A2693D ; # flow
set fgod  #d9b38c
set tcol  #ff8888 ; # temperature
set tgod  #ffc6c6
set wcol  #a2693d ; # weight
set bg    #FBFBFF

# --- the live vectors de1app grows during a shot (subset that's charted) ---
blt::vector create espresso_elapsed espresso_pressure espresso_pressure_goal \
    espresso_pressure_delta espresso_flow espresso_flow_2x espresso_flow_goal \
    espresso_flow_goal_2x espresso_flow_delta espresso_flow_weight \
    espresso_flow_weight_2x espresso_flow_weight_raw espresso_weight \
    espresso_weight_chartable espresso_resistance espresso_resistance_weight \
    espresso_temperature_basket espresso_temperature_basket10th \
    espresso_temperature_mix espresso_temperature_goal espresso_temperature_goal10th \
    espresso_state_change espresso_water_dispensed
# god (comparison) vectors - empty unless BB_GOD
blt::vector create god_espresso_pressure god_espresso_flow \
    god_espresso_flow_weight god_espresso_temperature_basket
# static profile-preview ("explanation chart") vectors
blt::vector create ec_elapsed ec_elapsed_flow ec_pressure ec_flow ec_temp

set SM linear ;# live_graph_smoothing_technique
set EM quadratic ;# preview_graph_smoothing_technique

proc newgraph {w h0 ymin ymax majorticks subdiv} {
    global CW CH CHROME CLABELS bg
    blt::graph $w -width $CW -height $CH -plotbackground $bg -background $bg \
        -borderwidth 1 -plotrelief flat -plotpady 0 -plotpadx 10 \
        -buffergraph 1 -bufferelements 0 -bufferchrome $CHROME -cachelabels $CLABELS
    $w axis configure x -tickfont {Helvetica 6} -hide [expr {!$::TICKS}]
    $w axis configure y -tickfont {Helvetica 6} -min $ymin -max $ymax -subdivisions [expr {$::SUBDIV0>0?$::SUBDIV0:$subdiv}] -hide [expr {!$::TICKS}]
    if {$majorticks ne ""} { $w axis configure y -majorticks $majorticks }
    $w grid configure -hide 0 -minor $::MINORG -color #DDDDDD -dashes ""
    $w legend configure -hide yes
    return $w
}

# ---------------- PRESSURE chart ----------------
newgraph .p 0 0.0 12.0 {1 3 5 7 9 11} 5
.p element create line_espresso_pressure_goal -xdata espresso_elapsed -ydata espresso_pressure_goal -symbol none -label "" -linewidth [rx 8] -color $pcol -smooth $SM -pixels 0 -dashes {5 5}
.p element create line_espresso_pressure -xdata espresso_elapsed -ydata espresso_pressure -symbol none -label "" -linewidth [rx 10] -color $pcol -smooth $SM -pixels 0
if {$GODL} { .p element create god_line_espresso_pressure -xdata espresso_elapsed -ydata god_espresso_pressure -symbol none -label "" -linewidth [rx 20] -color $pgod -smooth $SM -pixels 0 }
.p element create line_espresso_state_change_1 -xdata espresso_elapsed -ydata espresso_state_change -label "" -linewidth [rx 6] -color #AAAAAA -pixels 0
if {$PREVIEW} { .p element create line_ec_pressure -xdata ec_elapsed -ydata ec_pressure -label "" -linewidth [rx 15] -color $pcol -smooth $EM -pixels 0 }

# ---------------- FLOW chart ----------------
newgraph .f 0 0.0 8.01 {1 2 3 4 5 6 7 8} 2
.f element create line_espresso_flow_goal -xdata espresso_elapsed -ydata espresso_flow_goal -symbol none -label "" -linewidth [rx 8] -color $fcol -smooth $SM -pixels 0 -dashes {5 5}
.f element create line_espresso_flow -xdata espresso_elapsed -ydata espresso_flow -symbol none -label "" -linewidth [rx 12] -color $fcol -smooth $SM -pixels 0
if {$SCALE} {
    .f element create line_espresso_flow_weight -xdata espresso_elapsed -ydata espresso_flow_weight -symbol none -label "" -linewidth [rx 6] -color $wcol -smooth $SM -pixels 0
    if {$GODL} { .f element create god_line_espresso_flow_weight -xdata espresso_elapsed -ydata god_espresso_flow_weight -symbol none -label "" -linewidth [rx 12] -color $fgod -smooth $SM -pixels 0 }
}
if {$GODL} { .f element create god_line_espresso_flow -xdata espresso_elapsed -ydata god_espresso_flow -symbol none -label "" -linewidth [rx 24] -color $fgod -smooth $SM -pixels 0 }
.f element create line_espresso_state_change_2 -xdata espresso_elapsed -ydata espresso_state_change -label "" -linewidth [rx 6] -color #AAAAAA -pixels 0
if {$PREVIEW} { .f element create line_ec_flow -xdata ec_elapsed_flow -ydata ec_flow -label "" -linewidth [rx 15] -color $fcol -smooth $EM -pixels 0 }

# ---------------- TEMPERATURE chart ----------------
newgraph .t 0 80.0 100.0 "" 5
.t element create line_espresso_temperature_goal -xdata espresso_elapsed -ydata espresso_temperature_goal -symbol none -label "" -linewidth [rx 8] -color $tcol -smooth $SM -pixels 0 -dashes {5 5}
.t element create line_espresso_temperature_basket -xdata espresso_elapsed -ydata espresso_temperature_basket -symbol none -label "" -linewidth [rx 12] -color $tcol -smooth $SM -pixels 0
if {$PREVIEW} { .t element create line_ec_temp -xdata ec_elapsed -ydata ec_temp -label "" -linewidth [rx 15] -color $tcol -smooth $EM -pixels 0 }
if {$GODL} { .t element create god_line_espresso_temperature_basket -xdata espresso_elapsed -ydata god_espresso_temperature_basket -symbol none -label "" -linewidth [rx 24] -color $tgod -smooth $SM -pixels 0 }
.t element create line_espresso_state_change_3 -xdata espresso_elapsed -ydata espresso_state_change -label "" -linewidth [rx 6] -color #AAAAAA -pixels 0

pack .p .f .t -side top -fill both
wm geometry . +20+20
update

# ---- static profile preview (loaded once when a profile is selected) ----
proc load_profile_preview {} {
    foreach v {ec_elapsed ec_elapsed_flow ec_pressure ec_flow ec_temp} { $v length 0 }
    # a typical pressure-profile shot shape over 40s
    for {set i 0} {$i <= 40} {incr i} {
        set t $i
        ec_elapsed append $t
        ec_elapsed_flow append $t
        ec_pressure append [expr {$t<6 ? 2.0+$t : ($t<10 ? 9.0 : 6.0)}]
        ec_flow append [expr {$t<6 ? 4.0 : 2.0}]
        ec_temp append [expr {92.0}]
    }
}
load_profile_preview

# ---- god shot overlay (optional comparison curve, fixed) ----
proc load_god {} {
    foreach v {god_espresso_pressure god_espresso_flow god_espresso_flow_weight god_espresso_temperature_basket} { $v length 0 }
    if {!$::GOD} return
    set n [expr {int($::SECS*$::HZ)}]
    for {set i 0} {$i < $n} {incr i} {
        set t [expr {$i/double($::HZ)}]
        god_espresso_pressure append [format %.2f [expr {6.0+3.0*sin($t/3.0)}]]
        god_espresso_flow append [format %.2f [expr {2.2+1.0*sin($t/4.0)}]]
        god_espresso_flow_weight append [format %.2f [expr {2.0+0.9*sin($t/4.0)}]]
        god_espresso_temperature_basket append [expr {92.0+0.5*sin($t)}]
    }
}
load_god

# ---- one live sample appended to all charted vectors (mirrors gui.tcl) ----
proc r2 {x} { format %.2f $x }
set scv 6
proc live_sample {i} {
    global scv SCALE
    set t [expr {$i/double($::HZ)}]
    set p [expr {6.0+3.0*sin($t/3.0)+0.4*sin($t*7.0)}]
    set fl [expr {2.2+1.2*sin($t/4.0+1.0)+0.2*sin($t*9.0)}]
    set wt [expr {$fl*0.9}]
    espresso_elapsed append $t
    espresso_pressure append [r2 $p]
    espresso_pressure_goal append [expr {$t<8?9.0:6.0}]
    espresso_pressure_delta append [r2 [expr {abs(0.2*sin($t*5))}]]
    espresso_flow append [r2 $fl]
    espresso_flow_2x append [r2 [expr {2.0*$fl}]]
    espresso_flow_goal append [expr {$t<8?-1:2.0}]
    espresso_flow_goal_2x append [expr {$t<8?-1:4.0}]
    espresso_flow_delta append [r2 [expr {abs(0.3*sin($t*5))}]]
    espresso_resistance append [r2 [expr {$p/pow(($fl>0.1?$fl:0.1),2)}]]
    if {$SCALE} {
        espresso_flow_weight append [r2 $wt]
        espresso_flow_weight_2x append [r2 [expr {2.0*$wt}]]
        espresso_flow_weight_raw append [r2 $wt]
        espresso_resistance_weight append [r2 [expr {$p/pow(($wt>0.1?$wt:0.1),2)}]]
        espresso_weight append [r2 [expr {$t*0.5}]]
        espresso_weight_chartable append [r2 [expr {0.10*$t*0.5}]]
        espresso_water_dispensed append [r2 [expr {$t*0.6}]]
    }
    espresso_temperature_basket append [expr {92.0+0.5*sin($t)}]
    espresso_temperature_basket10th append [r2 [expr {(92.0+0.5*sin($t))/10.0}]]
    espresso_temperature_mix append [expr {88.0+0.5*sin($t)}]
    espresso_temperature_goal append 92.0
    espresso_temperature_goal10th append 9.2
    set scv [expr {($i % 80 < 40) ? 6 : -6}]
    espresso_state_change append $scv
}

proc reset_live {} {
    foreach v {espresso_elapsed espresso_pressure espresso_pressure_goal \
        espresso_pressure_delta espresso_flow espresso_flow_2x espresso_flow_goal \
        espresso_flow_goal_2x espresso_flow_delta espresso_flow_weight \
        espresso_flow_weight_2x espresso_flow_weight_raw espresso_weight \
        espresso_weight_chartable espresso_resistance espresso_resistance_weight \
        espresso_temperature_basket espresso_temperature_basket10th \
        espresso_temperature_mix espresso_temperature_goal espresso_temperature_goal10th \
        espresso_state_change espresso_water_dispensed} { $v length 0 }
}

if {$FIXEDX} {
    foreach g {.p .f .t} { $g axis configure x -min 0 -max $SECS }
}

# Set the live chart x-axis max for this frame's elapsed time, per XMODE.
# Returns 1 if the max changed (i.e. the axes/chrome will move this frame).
set ::lastxmax -1
proc set_xmax {t} {
    global XMODE lastxmax
    if {$XMODE eq "pin"} { return 0 }
    if {$XMODE eq "grow"} {
        set m [expr {$t < 1.0 ? 1.0 : $t}]
    } elseif {[string match "step*" $XMODE]} {
        set s [string range $XMODE 4 end]   ;# step seconds, e.g. step0.5
        set m [expr {(floor($t/$s)+1)*$s}]
    } else {
        set m $t
    }
    if {$m != $lastxmax} {
        foreach g {.p .f .t} { $g axis configure x -min 0 -max $m }
        set lastxmax $m
        return 1
    }
    return 0
}

# ---- the live shot: append at the real cadence, redraw to window each frame ----
set N [expr {int($SECS*$HZ)}]
reset_live; update idletasks
set t0 [clock microseconds]
for {set i 0} {$i < $N} {incr i} {
    live_sample $i
    if {!$FIXEDX} { set_xmax [expr {$i/double($HZ)}] }
    update idletasks
}
set ms [expr {([clock microseconds]-$t0)/1000.0/$N}]
emit [format "CHROME=%s CACHELABELS=%s XMODE=%-6s SCALE=%s FACTOR=%s GOD=%s :: %d frames, %.3f ms/frame  (3 charts %dx%d)" \
        $CHROME $CLABELS $XMODE $SCALE $F $GOD $N $ms $CW $CH]
close $::fd
exit 0
