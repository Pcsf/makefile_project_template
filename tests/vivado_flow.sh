#!/usr/bin/env bash
# Self-test for out-of-context synthesis and post-route checks in vivado.mk.
#
#   tests/vivado_flow.sh        vivado must be on PATH
#
# Each property is shown failing as well as passing: the I/O-buffer probe is
# shown to count buffers on an in-context run, and the hook is shown failing
# the build when it raises an error.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -r "$here/../test/vivado_flow/." "$work/"
cp "$work/project.mk.in" "$work/project.mk"
echo "include $here/../Makefile" > "$work/Makefile"

pass=0; fail=0
ok()  { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | tail -20 | sed 's/^/          /'; fail=$((fail + 1)); }

mk() { timeout 1800 make -C "$work" --no-print-directory "$@" 2>&1; }
iobs() { # bonded I/O buffers in the post-synthesis utilisation report
    awk -F'|' '/Bonded IOB/ { gsub(/ /, "", $3); print $3; exit }' \
        "$work/build/nonproject/post_synth_utilization.rpt" 2>/dev/null
}

echo "vivado flow self-test"
mk scan >/dev/null

out="$(mk synth VIVADO_SYNTH_MODE=)"; rc=$?
n="$(iobs)"
[ $rc -eq 0 ] && [ -n "$n" ] && [ "$n" -gt 0 ] && ok "in-context synthesis inserts I/O buffers ($n)" \
    || bad "in-context synthesis inserts I/O buffers (rc=$rc, iob='$n')" "$out"

out="$(mk impl)"; rc=$?
n="$(iobs)"
[ $rc -eq 0 ] && ok "out-of-context implementation completes" || bad "out-of-context implementation completes (rc=$rc)" "$out"
[ "$n" = "0" ] && ok "out-of-context synthesis inserts no I/O buffers" \
    || bad "out-of-context synthesis inserts no I/O buffers (iob='$n')" "$out"
printf '%s\n' "$out" | grep -q 'POST-ROUTE HOOK RAN' && ok "post-route hook runs in the build session" \
    || bad "post-route hook runs in the build session" "$out"

out="$(mk impl VIVADO_POST_ROUTE_TCL='hooks/marker.tcl hooks/fail.tcl')"; rc=$?
[ $rc -ne 0 ] && printf '%s\n' "$out" | grep -q 'planted post-route violation' \
    && ok "a failing hook fails the build" || bad "a failing hook fails the build (rc=$rc)" "$out"

out="$(mk bitstream)"; rc=$?
[ $rc -ne 0 ] && printf '%s\n' "$out" | grep -qi 'out.of.context' \
    && ok "bitstream refuses an out-of-context design" || bad "bitstream refuses an out-of-context design (rc=$rc)" "$out"
printf '%s\n' "$out" | grep -q '\[FLOW\] synthesis' \
    && bad "bitstream refuses before synthesis" "$out" || ok "bitstream refuses before synthesis"

echo "  ----"
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
