#!/usr/bin/env bash
# Self-test for make/verdict.mk.
#
# Every case that must FAIL is run alongside the case that must PASS. A verdict
# rule proven only against a passing run is not proven: the failure it exists to
# catch is exactly the one nobody sees.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/Makefile" <<'MK'
include VERDICT_MK
probe:
	$(call _test_verdict,SELFTEST)
MK
sed -i "s|VERDICT_MK|$here/../make/verdict.mk|" "$work/Makefile"

pass=0; fail=0

run() { # run <expect:pass|fail> <name> <make-args...>
    local expect="$1" name="$2"; shift 2
    local out rc
    out="$(make -s -C "$work" probe "$@" 2>&1)"; rc=$?
    local got; [ $rc -eq 0 ] && got=pass || got=fail
    if [ "$got" = "$expect" ]; then
        printf '  ok    %-44s (%s)\n' "$name" "$got"; pass=$((pass+1))
    else
        printf '  FAIL  %-44s expected %s, got %s\n' "$name" "$expect" "$got"
        printf '%s\n' "$out" | sed 's/^/          /'; fail=$((fail+1))
    fi
}

printf 'Error: check 3 failed\nNote: done\n' > "$work/red.log"
printf 'Note: everything fine\nTEST COMPLETE\n'  > "$work/green.log"
: > "$work/empty.log"

FAILPAT='^(Error|Failure|Fatal):'

echo "verdict.mk self-test"
run fail "fail pattern present"          TEST_LOG="$work/red.log"   TEST_FAIL_PATTERN="$FAILPAT"
run pass "fail pattern absent"           TEST_LOG="$work/green.log" TEST_FAIL_PATTERN="$FAILPAT"
run fail "pass pattern missing"          TEST_LOG="$work/red.log"   TEST_PASS_PATTERN='TEST COMPLETE'
run pass "pass pattern present"          TEST_LOG="$work/green.log" TEST_PASS_PATTERN='TEST COMPLETE'
run fail "transcript missing"            TEST_LOG="$work/absent.log" TEST_FAIL_PATTERN="$FAILPAT"
run fail "transcript empty"              TEST_LOG="$work/empty.log" TEST_FAIL_PATTERN="$FAILPAT"
run fail "no pattern configured"         TEST_LOG="$work/green.log"
run fail "TEST_LOG unset"                TEST_FAIL_PATTERN="$FAILPAT"
run pass "TEST_CHECK=0 skips a red run"  TEST_LOG="$work/red.log"   TEST_FAIL_PATTERN="$FAILPAT" TEST_CHECK=0
run fail "both patterns, fail wins"      TEST_LOG="$work/red.log"   TEST_FAIL_PATTERN="$FAILPAT" TEST_PASS_PATTERN='Note:'
run fail "unusable fail pattern"         TEST_LOG="$work/green.log" TEST_FAIL_PATTERN='^('
run fail "unusable pass pattern"         TEST_LOG="$work/green.log" TEST_PASS_PATTERN='^('

# The toolchain defaults are data, and a truncated one looks like a working
# pattern until a failing run walks past it.
printf '# ** Error: tb.vhd(12): check failed\n' > "$work/msim.log"
printf 'tb.vhd:9:5:@0ms:(assertion error): check failed\n' > "$work/ghdl.log"
run fail "simulator default: transcript form A" TEST_LOG="$work/msim.log" TEST_FAIL_PATTERN='\*\* (Error|Fatal):'
run fail "simulator default: transcript form B" TEST_LOG="$work/ghdl.log" TEST_FAIL_PATTERN='\(assertion (error|failure)\)|\(report (error|failure)\)|^ghdl:error:'

echo "  ----"
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
