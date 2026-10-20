# pnr/mmmc.tcl — Innovus 23.14 (Stylus) multi-mode multi-corner setup for kh_jtag_top (stage 1).
# Read by pnr/pnr.tcl through read_mmmc. Setup is checked at slow/125C, hold at fast/0C.

if {![info exists ::env(GSCLIB045_ROOT)]} { error "set GSCLIB045_ROOT to <dir>/gsclib045_all_v4.7/gsclib045" }
set LIB_ROOT $::env(GSCLIB045_ROOT)
set SDC      [file normalize [file join [file dirname [info script]] .. syn constraints.sdc]]

create_library_set -name libs_slow -timing [list $LIB_ROOT/timing/slow_vdd1v0_basicCells.lib]   ;# PVT_0P9V_125C
create_library_set -name libs_fast -timing [list $LIB_ROOT/timing/fast_vdd1v0_basicCells.lib]   ;# PVT_1P1V_0C

create_timing_condition -name tc_slow -library_sets libs_slow
create_timing_condition -name tc_fast -library_sets libs_fast

create_rc_corner -name rc_slow -qrc_tech $LIB_ROOT/qrc/qx/gpdk045.tch -temperature 125
create_rc_corner -name rc_fast -qrc_tech $LIB_ROOT/qrc/qx/gpdk045.tch -temperature 0

create_delay_corner -name dc_slow -timing_condition tc_slow -rc_corner rc_slow
create_delay_corner -name dc_fast -timing_condition tc_fast -rc_corner rc_fast

create_constraint_mode -name func -sdc_files [list $SDC]

create_analysis_view -name view_setup -constraint_mode func -delay_corner dc_slow
create_analysis_view -name view_hold  -constraint_mode func -delay_corner dc_fast

set_analysis_view -setup view_setup -hold view_hold
