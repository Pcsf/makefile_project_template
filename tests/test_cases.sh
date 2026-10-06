#!/usr/bin/env bash
# Self-test for the TESTS case list behind `make test`.
#
#   tests/test_cases.sh <toolchain>      toolchain: ghdl | modelsim | vivado
#
# Runs the fixture in test/test_cases with the named toolchain, whose tools must
# be on PATH. Every claim is checked in both directions: a case list that only
# ever passes has not shown it can fail.
set -u

tc="${1:?usage: $0 <ghdl|modelsim|vivado>}"
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -r "$here/../test/test_cases/." "$work/"
sed "s|@TOOLCHAIN@|$tc|" "$work/project.mk.in" > "$work/project.mk"
echo "include $here/../Makefile" > "$work/Makefile"

pass=0; fail=0
ok()  { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | tail -25 | sed 's/^/          /'; fail=$((fail + 1)); }

mk() { # mk <args...> — make in the fixture, wall-clock bounded so a hang fails
    timeout 900 make -C "$work" --no-print-directory "$@" 2>&1
}
log() { cat "$work/build/test/$1.log" 2>/dev/null; }

echo "test cases self-test ($tc)"
mk scan >/dev/null

out="$(mk test TESTS='default seven mode_b data')"; rc=$?
[ $rc -eq 0 ] && ok "passing cases pass" || bad "passing cases pass (rc=$rc)" "$out"

log seven  | grep -qi 'VALUE=7 MODE=MODE_A' && ok "generic reaches its case" \
    || bad "generic reaches its case" "$(log seven)"
log mode_b | grep -qi 'VALUE=3 MODE=MODE_B' && ok "enumeration generic and second generic" \
    || bad "enumeration generic and second generic" "$(log mode_b)"
log default | grep -qi 'VALUE=0 MODE=MODE_A' && ok "case without generics keeps defaults" \
    || bad "case without generics keeps defaults" "$(log default)"
log data   | grep -q 'DATA=42' && ok "file opened relative to the project root" \
    || bad "file opened relative to the project root" "$(log data)"

out="$(mk test TESTS=hang)"; rc=$?
[ $rc -ne 0 ] && ok "case hitting its time limit fails" \
    || bad "case hitting its time limit fails (rc=0)" "$out"
[ $rc -ne 124 ] && ok "time limit ends the run, not the wall clock" \
    || bad "time limit ends the run, not the wall clock" "$out"

out="$(mk test TESTS='fail default')"; rc=$?
[ $rc -ne 0 ] && ok "a failing case fails the list" || bad "a failing case fails the list (rc=0)" "$out"
log default | grep -q 'CASE PASS' && ok "cases after a failure still run" \
    || bad "cases after a failure still run" "$out"
printf '%s\n' "$out" | grep -Eq 'FAILED.*\bfail\b' && ok "summary names the failed case" \
    || bad "summary names the failed case" "$out"

out="$(mk test TESTS=)"; rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q 'VALUE=0' && ok "empty TESTS runs the single default top" \
    || bad "empty TESTS runs the single default top (rc=$rc)" "$out"

echo "  ----"
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
