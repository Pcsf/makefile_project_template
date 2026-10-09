#!/usr/bin/env bash
# Self-test for a tree that has never been scanned, as a fresh clone is: the
# Makefile.mk fragments are gitignored, so a clone has none.
#
#   tests/fresh_clone.sh <toolchain>      toolchain: ghdl | modelsim | vivado
#
# Every check starts from a new copy of test/test_cases with no fragments.
set -u

tc="${1:?usage: $0 <ghdl|modelsim|vivado>}"
here="$(cd "$(dirname "$0")" && pwd)"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

pass=0; fail=0
ok()  { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | tail -25 | sed 's/^/          /'; fail=$((fail + 1)); }

fresh() { # fresh — a new unscanned copy of the fixture; prints its path
    local w; w="$(mktemp -d -p "$root")"
    cp -r "$here/../test/test_cases/." "$w/"
    sed "s|@TOOLCHAIN@|$tc|" "$w/project.mk.in" > "$w/project.mk"
    echo "include $here/../Makefile" > "$w/Makefile"
    echo "$w"
}
mk() { # mk <dir> <args...> — wall-clock bounded so a hang fails
    local d="$1"; shift
    timeout 900 make -C "$d" --no-print-directory "$@" 2>&1
}
fragments() { find "$1" -name Makefile.mk | wc -l; }

echo "fresh clone self-test ($tc)"

w="$(fresh)"
[ "$(fragments "$w")" -eq 0 ] && ok "a copy starts with no fragments" || bad "a copy starts with no fragments"
mk "$w" scan >/dev/null
[ "$(fragments "$w")" -gt 0 ] && ok "the fragment count sees a scan" || bad "the fragment count sees a scan"

w="$(fresh)"
out="$(mk "$w" test TESTS=default)"; rc=$?
[ $rc -eq 0 ] && grep -q 'CASE PASS' "$w/build/test/default.log" 2>/dev/null \
    && ok "make test TESTS=<case> runs first time" || bad "make test TESTS=<case> runs first time (rc=$rc)" "$out"

w="$(fresh)"
out="$(mk "$w" test TESTS='default fail')"; rc=$?
[ $rc -ne 0 ] && grep -q 'CASE PASS' "$w/build/test/default.log" 2>/dev/null \
    && ok "a failing case still fails first time" || bad "a failing case still fails first time (rc=$rc)" "$out"

w="$(fresh)"
out="$(mk "$w" info)"; rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q 'tb_generic.vhd' \
    && ok "make info lists the sources first time" || bad "make info lists the sources first time (rc=$rc)" "$out"

w="$(fresh)"
out="$(mk "$w")"; rc=$?
[ $rc -eq 0 ] && ok "plain make scans and builds first time" || bad "plain make scans and builds first time (rc=$rc)" "$out"

for t in clean distclean help; do
    w="$(fresh)"
    out="$(mk "$w" $t)"; rc=$?
    [ $rc -eq 0 ] && [ "$(fragments "$w")" -eq 0 ] \
        && ok "make $t works and does not scan" || bad "make $t works and does not scan (rc=$rc, $(fragments "$w") fragments)" "$out"
done

echo "  ----"
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
