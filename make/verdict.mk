# ==============================================================================
# verdict.mk — Toolchain-neutral verdict for `make test`
# Included by common.mk. Knows no toolchain, simulator, or vendor.
# ==============================================================================
#
# Some runners report failure through their exit status and some do not. A
# runner that always exits 0 makes an unchecked `make test` report success on a
# run where every check failed, and a green build that proves nothing is worse
# than a red one. This macro is the verdict for that second kind: it reads the
# transcript the run left behind and decides.
#
# A toolchain whose runner exits honestly does not call this at all — make's own
# exit-status propagation is already the verdict there.
#
#   TEST_LOG           transcript to read. Required.
#   TEST_FAIL_PATTERN  extended regex; any match fails the run.
#   TEST_PASS_PATTERN  extended regex that MUST appear, or the run fails. A
#                      completion marker is a project convention, so the
#                      framework never supplies one; declare it in project.mk.
#   TEST_CHECK         0 skips the verdict, for a run EXPECTED to fail: a red
#                      phase asserts the inverse itself against the same
#                      transcript. Command line only — a project that sets it
#                      permanently has switched the check off.
#
# At least one pattern must be set. A verdict with nothing to match is not a
# verdict, and passing in that state would be the exact failure this file
# exists to prevent, so it fails loudly instead.
#
# Patterns are passed to grep -E inside single quotes; one containing a single
# quote will not survive. An unusable pattern fails the run rather than passing
# it: grep answers 'no match' and 'I could not read that' with different exit
# statuses, and treating the second as the first is how a check stops checking.
#
# A pattern must also survive make itself. An unescaped '#' starts a comment and
# silently truncates the rest of the assignment, so route one through $(_HASH)
# or write a pattern that does not need it.

TEST_LOG          ?=
TEST_FAIL_PATTERN ?=
TEST_PASS_PATTERN ?=
TEST_CHECK        ?= 1

# $(call _test_verdict,<LABEL>) — LABEL tags the output with the toolchain's short name.
define _test_verdict
	@label='$(strip $(1))'; log='$(abspath $(TEST_LOG))'; \
	if [ "$(strip $(TEST_CHECK))" = "0" ]; then \
	    echo "[$$label] Verdict SKIPPED (TEST_CHECK=0). Transcript: $(TEST_LOG)"; \
	    exit 0; \
	fi; \
	if [ -z '$(strip $(TEST_FAIL_PATTERN))' ] && [ -z '$(strip $(TEST_PASS_PATTERN))' ]; then \
	    echo "[$$label] FAILED — no verdict configured."; \
	    echo "[$$label] Set TEST_FAIL_PATTERN, TEST_PASS_PATTERN, or both."; \
	    exit 1; \
	fi; \
	if [ -z "$(strip $(TEST_LOG))" ]; then \
	    echo "[$$label] FAILED — TEST_LOG is not set; there is no transcript to read."; \
	    exit 1; \
	fi; \
	if [ ! -s "$$log" ]; then \
	    echo "[$$label] FAILED — no transcript at $(TEST_LOG); the run produced nothing."; \
	    exit 1; \
	fi; \
	$(if $(strip $(TEST_FAIL_PATTERN)),\
	grep -Eq '$(TEST_FAIL_PATTERN)' "$$log"; g=$$?; \
	if [ $$g -gt 1 ]; then \
	    echo "[$$label] FAILED — TEST_FAIL_PATTERN is not a usable regex: $(TEST_FAIL_PATTERN)"; \
	    exit 1; \
	fi; \
	if [ $$g -eq 0 ]; then \
	    echo "[$$label] FAILED — transcript matched TEST_FAIL_PATTERN:"; \
	    grep -E '$(TEST_FAIL_PATTERN)' "$$log" | head -20 | sed "s/^/[$$label]     /"; \
	    echo "[$$label] Full transcript: $(TEST_LOG)"; \
	    exit 1; \
	fi; ) \
	$(if $(strip $(TEST_PASS_PATTERN)),\
	grep -Eq '$(TEST_PASS_PATTERN)' "$$log"; g=$$?; \
	if [ $$g -gt 1 ]; then \
	    echo "[$$label] FAILED — TEST_PASS_PATTERN is not a usable regex: $(TEST_PASS_PATTERN)"; \
	    exit 1; \
	fi; \
	if [ $$g -ne 0 ]; then \
	    echo "[$$label] FAILED — TEST_PASS_PATTERN never appeared: $(TEST_PASS_PATTERN)"; \
	    echo "[$$label] The run ended before it reported completion."; \
	    echo "[$$label] Full transcript: $(TEST_LOG)"; \
	    exit 1; \
	fi; ,\
	echo "[$$label] NOTE: TEST_PASS_PATTERN is unset — a run that stops early still passes."; \
	echo "[$$label]       Declare the completion marker in project.mk."; ) \
	echo "[$$label] PASSED — transcript checked ($(TEST_LOG))."
endef
