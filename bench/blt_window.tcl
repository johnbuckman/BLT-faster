#!/usr/bin/env wish
# Realistic WINDOW-draw benchmark: mirrors the de1app live path.
# Per sample: append to vectors, then `update idletasks` to force the
# graph's deferred redraw to the on-screen window (DisplayGraph path,
# with double-buffer + backing store, exactly as the app uses it).
#
# Knobs:
#   BB_DBUF  - 1/0 doubleBuffer (default 1)
#   BB_BUF   - 1/0 bufferelements/backingStore (default 1)
#   BB_FIXEDX- 1 = fixed x-axis range (static chrome), 0 = autoscale (default 0)
package require Tk
package require BLT
proc envd {k d} { return [expr {[info exists ::env($k)] ? $::env($k) : $d}] }
set DBUF  [envd BB_DBUF 1]
set BUF   [envd BB_BUF 1]
set FIXEDX [envd BB_FIXEDX 0]
set TICKS [envd BB_TICKS 1]
set GRID  [envd BB_GRID 1]
set ELEMS [envd BB_ELEMS 1]
set OUT [lindex $argv 0]; if {$OUT eq ""} { set OUT /tmp/blt_window.txt }
set ::fd [open $OUT a]; proc emit {m} { puts $::fd $m; flush $::fd; puts $m }

set CW 1240; set CH 406
blt::vector create ev ep ef epg efg efw esc efd epd
proc build {wn ymax} {
    global CW CH DBUF BUF
    blt::graph $wn -width $CW -height $CH -plotpadx 10 -plotpady 0 -borderwidth 1 \
        -plotrelief flat -buffergraph $DBUF -bufferelements $BUF
    if {$::ELEMS} {
    $wn element create e_pg -xdata ev -ydata epg -symbol none -label "" -linewidth 8 -color #66B6FF -smooth linear -pixels 0 -dashes {5 5}
    $wn element create e_p  -xdata ev -ydata ep  -symbol none -label "" -linewidth 10 -color #66B6FF -smooth linear -pixels 0
    $wn element create e_sc -xdata ev -ydata esc -label "" -linewidth 6 -color #AAAAAA -pixels 0
    $wn element create e_pd -xdata ev -ydata epd -symbol none -label "" -linewidth 2 -color #40dc94 -pixels 0 -smooth linear
    }
    $wn grid configure -dashes "" -color #DDDDDD -hide [expr {!$::GRID}] -minor 1
    $wn axis configure x -tickfont {Helvetica 6} -linewidth 2 -hide [expr {!$::TICKS}]
    $wn axis configure y -tickfont {Helvetica 6} -min 0.0 -max $ymax -subdivisions 5 -hide [expr {!$::TICKS}]
    $wn legend configure -hide yes
}
build .pg 12.0
# second graph reuses flow-ish elements but keep it simple: one more graph
blt::graph .fg -width $CW -height $CH -plotpadx 10 -plotpady 0 -borderwidth 1 \
    -plotrelief flat -buffergraph $DBUF -bufferelements $BUF
if {$ELEMS} {
.fg element create f_fg -xdata ev -ydata efg -symbol none -label "" -linewidth 8 -color #A2693D -smooth linear -pixels 0 -dashes {5 5}
.fg element create f_f  -xdata ev -ydata ef  -symbol none -label "" -linewidth 12 -color #A2693D -smooth linear -pixels 0
.fg element create f_w  -xdata ev -ydata efw -symbol none -label "" -linewidth 6 -color #a2693d -smooth linear -pixels 0
.fg element create f_d  -xdata ev -ydata efd -symbol none -label "" -linewidth 2 -color #98c5ff -pixels 0 -smooth linear
}
.fg grid configure -dashes "" -color #DDDDDD -hide [expr {!$GRID}] -minor 1
.fg axis configure x -tickfont {Helvetica 6} -linewidth 2 -hide [expr {!$TICKS}]
.fg axis configure y -tickfont {Helvetica 6} -min 0.0 -max 8.0 -hide [expr {!$TICKS}]
.fg legend configure -hide yes

if {$FIXEDX} {
    .pg axis configure x -min 0 -max 45
    .fg axis configure x -min 0 -max 45
}
pack .pg .fg -side top -fill both
wm geometry . 1280x820+40+40
update

set NS 450; set HZ 10.0
proc reset {} { foreach v {ev ep ef epg efg efw esc efd epd} { $v length 0 } }
proc samp {t i} {
    set p [expr {6.0 + 3.0*sin($t/3.0) + 0.4*sin($t*7.0)}]
    set f [expr {2.2 + 1.2*sin($t/4.0 + 1.0) + 0.2*sin($t*9.0)}]
    ev append $t; ep append [format %.2f $p]; ef append [format %.2f $f]
    epg append [expr {$t<8?9.0:6.0}]; efg append [expr {$t<8?-1:2.0}]
    efw append [format %.2f [expr {$f*0.9}]]
    esc append [expr {($i%80<40)?6:-6}]
    efd append [format %.2f [expr {abs(0.3*sin($t*5))}]]
    epd append [format %.2f [expr {abs(0.2*sin($t*5))}]]
}

# live: append one sample then force the deferred window redraw, like the app
proc live {} {
    reset; update idletasks
    set t0 [clock microseconds]
    for {set i 0} {$i<$::NS} {incr i} {
        samp [expr {$i/$::HZ}] $i
        update idletasks
    }
    expr {([clock microseconds]-$t0)/1000.0/$::NS}
}
# steady: full curve present, force a redraw each iteration (invalidate by re-touching a vector)
proc steady {reps} {
    reset; for {set i 0} {$i<$::NS} {incr i} { samp [expr {$i/$::HZ}] $i }
    update idletasks
    set t0 [clock microseconds]
    for {set r 0} {$r<$reps} {incr r} {
        # touch one element's data to force a redraw
        ep notify now
        update idletasks
    }
    expr {([clock microseconds]-$t0)/1000.0/$reps}
}

update idletasks
set lv [live]
set st [steady 200]
emit [format "DBUF=%s BUF=%s FIXEDX=%s TICKS=%s GRID=%s ELEMS=%s :: LIVE=%.3f  STEADY=%.3f ms/frame" $DBUF $BUF $FIXEDX $TICKS $GRID $ELEMS $lv $st]
close $::fd
exit 0
