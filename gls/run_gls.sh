#!/usr/bin/env bash
# gls/run_gls.sh — post-route gate-level simulation of tb/tb_tap.sv with SDF back-annotation (Xcelium).
# Run on the server from the project root, after pnr/pnr.tcl:
#   bash gls/run_gls.sh            # max (slow 0.9 V / 125 C) and min (fast 1.1 V / 0 C) corners
#   bash gls/run_gls.sh max|min    # one corner
# Inputs: pnr/out/kh_jtag_top.pnr.vg, pnr/out/kh_jtag_top.pnr.sdf, gsclib045 Verilog cell models
#         ($GSCLIB045_ROOT/verilog, GSCLIB045_ROOT = <dir>/gsclib045_all_v4.7/gsclib045).
# Logs:   gls/logs/gls_<corner>.log (simulation), gls/logs/gls_<corner>.sdf.log (SDF annotation)
set -u
CELL_DIR="${GSCLIB045_ROOT:?set GSCLIB045_ROOT to <dir>/gsclib045_all_v4.7/gsclib045}/verilog"
NETLIST=pnr/out/kh_jtag_top.pnr.vg
mkdir -p gls/logs

run_corner() {
    local corner=$1 cells defs
    if [ "$corner" = min ]; then
        cells=$CELL_DIR/fast_vdd1v0_basicCells.v
        defs="-define GLS -define GLS_MIN"
    else
        cells=$CELL_DIR/slow_vdd1v0_basicCells.v
        defs="-define GLS"
    fi
    # shellcheck disable=SC2086
    xrun -sv -vlogext .vg -timescale 1ns/1ps -incdir tb $defs -top tb_tap \
        tb/tb_tap.sv "$NETLIST" -v "$cells" \
        -xmlibdirname "gls/xcelium.d_$corner" -log "gls/logs/gls_$corner.log" -history_file "gls/logs/xrun_$corner.history" \
        > /dev/null 2>&1
    local rc=$?
    local summary
    summary=$(grep -E '^(ALL TESTS PASSED|[0-9]+ FAILURES)$' "gls/logs/gls_$corner.log" | tail -1)
    echo "gls $corner: xrun exit=$rc | ${summary:-no summary line}"
    [ "$rc" -eq 0 ] && [ "$summary" = "ALL TESTS PASSED" ]
}

status=0
case "${1:-both}" in
    max)  run_corner max || status=1 ;;
    min)  run_corner min || status=1 ;;
    both) run_corner max || status=1; run_corner min || status=1 ;;
    *)    echo "usage: $0 [max|min|both]"; exit 2 ;;
esac
exit $status
