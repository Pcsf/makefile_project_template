#!/usr/bin/env bash
# Self-test for simulating the real Xilinx IP in place of its stand-in.
#
#   tests/vivado_ip_sim.sh        vivado (and xsim) must be on PATH
#
# The fixture's IP is a 3-stage multiplier and its stand-in has no pipeline,
# so the latency the testbench measures says which one ran.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -r "$here/../test/vivado_ip_sim/." "$work/"
cp "$work/project.mk.in" "$work/project.mk"
echo "include $here/../Makefile" > "$work/Makefile"

pass=0; fail=0
ok()  { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | tail -20 | sed 's/^/          /'; fail=$((fail + 1)); }

mk() { timeout 1800 make -C "$work" --no-print-directory "$@" 2>&1; }

echo "vivado real-IP simulation self-test"
mk scan >/dev/null

out="$(mk test)"; rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q 'LATENCY=0' && ok "default run simulates the stand-in" \
    || bad "default run simulates the stand-in (rc=$rc)" "$out"

out="$(mk test XSIM_REAL_IP=1)"; rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q 'LATENCY=3' && ok "XSIM_REAL_IP=1 simulates the vendor model" \
    || bad "XSIM_REAL_IP=1 simulates the vendor model (rc=$rc)" "$out"

# Vivado's xsim.ini maps mult_gen's library into the install; an install that
# is writable would take the compile silently and the run above would pass.
[ -n "$(find "$work/build/xsim_ip/xsim.dir" -path '*mult_gen_v12_0*' -name '*.vdb' 2>/dev/null)" ] \
    && ok "the IP's libraries are compiled into the run's own xsim.dir" \
    || bad "the IP's libraries are compiled into the run's own xsim.dir" \
           "$(ls "$work/build/xsim_ip/xsim.dir" 2>&1)"

out="$(mk test)"; rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q 'LATENCY=0' && ok "switching back runs the stand-in again" \
    || bad "switching back runs the stand-in again (rc=$rc)" "$out"

echo "  ----"
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
