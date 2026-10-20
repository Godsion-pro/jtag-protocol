#!/usr/bin/env bash
# sim/check_openocd_tap.sh — Stage 1 criterion (b): OpenOCD finds the Verilated TAP over remote_bitbang.
# Run from the project root inside WSL:  bash sim/check_openocd_tap.sh
# Logs: sim/logs/build_rbb_tap.log, sim/logs/rbb_tap.log, sim/logs/openocd_tap.log
set -u
PORT=${PORT:-9999}
mkdir -p sim/logs

if ! make -C sim rbb_tap > sim/logs/build_rbb_tap.log 2>&1; then
    echo "BUILD FAILED"; tail -30 sim/logs/build_rbb_tap.log; exit 1
fi

./sim/obj_dir/Vrbb_tap +port="$PORT" > sim/logs/rbb_tap.log 2>&1 &
SIM=$!
for _ in $(seq 50); do
    grep -q 'listening' sim/logs/rbb_tap.log 2>/dev/null && break
    sleep 0.1
done

# After init: IDCODE (0x01) and both BYPASS codes (0x1F, 0x00) through OpenOCD's own scans.
# BYPASS expectation: 8 bits 0x4d in -> {in[6:0], 0} = 0x9a out (IEEE 1149.1-2013 10.1.1 b).
# Then a TRST* pulse from OpenOCD ('t', 'r') with BYPASS selected must restore IDCODE (7.2.1 f).
# That part runs as SVF (openocd/check_trst.svf): in OpenOCD 0.12 a bare drscan right after a TRST
# pulse hits an internal assertion (driver.c:166) because OpenOCD then models the TAP as bypassed.
timeout 60 openocd -f openocd/sim_tap.cfg \
    -c init \
    -c "irscan kh.tap 0x01" -c "echo \"IDCODE drscan: [drscan kh.tap 32 0]\"" \
    -c "irscan kh.tap 0x1f" -c "echo \"BYPASS(0x1f) drscan 0x4d: [drscan kh.tap 8 0x4d]\"" \
    -c "irscan kh.tap 0x00" -c "echo \"BYPASS(0x00) drscan 0x4d: [drscan kh.tap 8 0x4d]\"" \
    -c "svf openocd/check_trst.svf" \
    -c shutdown > sim/logs/openocd_tap.log 2>&1
OCD_RC=$?

for _ in $(seq 50); do kill -0 "$SIM" 2>/dev/null || break; sleep 0.1; done
kill "$SIM" 2>/dev/null
wait "$SIM" 2>/dev/null

echo "openocd exit=$OCD_RC"
grep -E 'tap/device found|IDCODE drscan|BYPASS\(0x|svf|error' sim/logs/openocd_tap.log
grep -E '^rbb:' sim/logs/rbb_tap.log

fail=0
grep -q 'tap/device found: 0xdeadbeef'        sim/logs/openocd_tap.log || fail=1
grep -q 'IDCODE drscan: deadbeef'             sim/logs/openocd_tap.log || fail=1
grep -q 'BYPASS(0x1f) drscan 0x4d: 9a'        sim/logs/openocd_tap.log || fail=1
grep -q 'BYPASS(0x00) drscan 0x4d: 9a'        sim/logs/openocd_tap.log || fail=1
grep -q 'svf file programmed successfully'   sim/logs/openocd_tap.log || fail=1
[ "$OCD_RC" -eq 0 ] || fail=1
if [ "$fail" -eq 0 ]; then echo "OPENOCD CHECK PASSED"; else echo "OPENOCD CHECK FAILED"; exit 1; fi
