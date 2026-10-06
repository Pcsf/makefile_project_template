# ==============================================================================
# ghdl.mk — GHDL VHDL simulator toolchain rules
# Handles: .vhd/.vhdl → analysis → elaboration → simulation (VCD output)
#
# ── Compilation order strategy ────────────────────────────────────────────────
# VHDL requires that packages and entities are analysed before any design unit
# that references them.  Three layers of defence are applied:
#
#   Layer 1 – VHDL_SRCS_DIR in project.mk: list directories in order; each
#              directory's file list is still auto-managed (.compile_order /
#              wildcard).  Use this for cross-directory ordering.
#   Layer 2 – per-directory .compile_order files (created by 'make scan',
#              never overwritten; controls within-directory order)
#   Layer 3 – silent pre-pass below (fully automatic, handles most cases)
#
# The pre-pass analyses every file once, ignoring errors.  Any file that
# succeeds pre-populates the work library.  The real pass then finds all
# previously-analysed units available and compiles in declared order.
# Circular dependencies (a design error) are the only case not handled.
# ==============================================================================

# ── Tool names ───────────────────────────────────────────────────────────────
# Defaulted rather than required. Without a default an unset variable expands to
# nothing and the recipe runs its own first flag as the command, which fails as
# "not found" and points at the flag rather than at the missing tool.
GHDL     ?= ghdl
GHDL_STD ?= 08

GHDL_WORKDIR      := $(BUILD_DIR)/ghdl_work
GHDL_PROJECT_FLAGS := $(GHDL_FLAGS)
GHDL_FLAGS         := --std=$(GHDL_STD) --workdir=$(GHDL_WORKDIR) \
                      -P$(GHDL_WORKDIR) $(GHDL_PROJECT_FLAGS)

VHDL_LIB_ANALYZE_TARGETS := $(addprefix analyze-lib-,$(VHDL_LIBS))

.PHONY: all analyze analyze-vhdl-libs elaborate simulate sim test test-compile test-run _help_ghdl $(VHDL_LIB_ANALYZE_TARGETS)

# Listed by 'make help' — see the TOOLCHAIN_HELP_TARGET hook in common.mk.
TOOLCHAIN_HELP_TARGET := _help_ghdl

_help_ghdl:
	@echo ""
	@echo "  GHDL targets:"
	@echo "    analyze    Analyse the VHDL sources"
	@echo "    elaborate  Elaborate GHDL_TOP"
	@echo "    simulate   Run the simulation — this is what 'all' builds"
	@echo "    sim        Alias for simulate"
	@echo "    test       Run the simulation and render a verdict"

all: simulate
sim: simulate

$(GHDL_WORKDIR):
	$(MKDIR) $(GHDL_WORKDIR)

# ── Named VHDL libraries ──────────────────────────────────────────────────────
define GHDL_VHDL_LIB_template
analyze-lib-$(1): $$(addprefix analyze-lib-,$$(VHDL_LIB_$(1)_DEPS)) | $$(GHDL_WORKDIR)
	@test -n "$$(strip $$(VHDL_LIB_$(1)_SRCS))" || { echo "[GHDL] No sources configured for VHDL library '$(1)'"; exit 1; }
	@echo "[GHDL] Analysing library '$(1)' ($$(words $$(VHDL_LIB_$(1)_SRCS)) file(s))..."
	@$$(foreach f,$$(VHDL_LIB_$(1)_SRCS),printf '  [GHDL-A:$(1)] %s\n' '$$(f)';)
	@$$(GHDL) -a $$(GHDL_FLAGS) $$(VHDL_LIB_$(1)_GHDL_FLAGS) \
	    --work=$(1) $$(VHDL_LIB_$(1)_SRCS) || \
	    { echo "[GHDL] FAILED compiling library '$(1)'"; exit 1; }
endef

$(foreach lib,$(VHDL_LIBS),$(eval $(call GHDL_VHDL_LIB_template,$(lib))))

analyze-vhdl-libs: $(VHDL_LIB_ANALYZE_TARGETS)

# ── Analysis ──────────────────────────────────────────────────────────────────
analyze: analyze-vhdl-libs | $(GHDL_WORKDIR)
	@echo "[GHDL] Analysing $(words $(VHDL_SRCS)) work-library VHDL file(s) (std=$(GHDL_STD))..."
	@echo "[GHDL] Pre-pass: pre-populating work library (errors silenced)..."
	@$(foreach f,$(VHDL_SRCS),\
	    $(GHDL) -a $(GHDL_FLAGS) $(f) 2>/dev/null;) true
	@echo "[GHDL] Final analysis pass:"
	@$(foreach f,$(VHDL_SRCS),\
	    printf '  [GHDL-A] %s\n' '$(f)' && \
	    $(GHDL) -a $(GHDL_FLAGS) $(f) || \
	    { echo '[GHDL] FAILED on: $(f)'; \
	      echo '[GHDL] Fix: check .compile_order or set VHDL_SRCS in project.mk'; \
	      exit 1; };)

# ── Elaboration ───────────────────────────────────────────────────────────────
elaborate: analyze
	@echo "[GHDL] Elaborating top entity '$(GHDL_TOP)'..."
	$(GHDL) -e $(GHDL_FLAGS) $(GHDL_TOP)

# ── The test verdict ──────────────────────────────────────────────────────────
# `simulate` is the developer-facing run: it writes a VCD and reports what it
# saw. `test` is the machine-facing one, and its exit status is the verdict.
#
# Two reasons the exit status of a bare run is not one, both measured on GHDL
# 6.0.0. An assertion at 'severity error' prints its message, the run continues
# to completion, and the process exits 0 — indistinguishable from a clean run.
# And a verification library that counts its own alerts raises no assertion at
# all; it reports in a summary line and ends normally, so the process exits 0
# with every check failed.
#
# --assert-level=error closes the first case by making an error-severity
# assertion stop the run. The second cannot be closed by a flag, because the
# summary wording belongs to the library, not to GHDL: declare the project's
# own TEST_FAIL_PATTERN or TEST_PASS_PATTERN for it.
#
#   GHDL_TEST_FLAGS  runtime flags for the verdict run. Lower it to
#                    --assert-level=failure for a testbench that reports
#                    several errors on purpose and checks the total itself.
GHDL_TEST_FLAGS   ?= --assert-level=error
TEST_TOP          ?= $(GHDL_TOP)
TEST_LOG          ?= $(BUILD_DIR)/test_$(TEST_TOP).log
TEST_FAIL_PATTERN ?= \(assertion (error|failure)\)|\(report (error|failure)\)|^ghdl:error:

TOOLCHAIN_HAS_TEST  := 1
TOOLCHAIN_HAS_CASES := 1

# One verdict run of TEST_TOP. TEST_GENERICS and TEST_TIME are the
# toolchain-neutral case settings described in common.mk; GHDL takes both at
# run time, so a case needs no elaboration of its own beyond the top.
test-compile: analyze

test-run: $(if $(strip $(TEST_COMPILED)),,analyze)
	@echo "[GHDL] Testing '$(TEST_TOP)'$(if $(strip $(TEST_GENERICS)), with $(strip $(TEST_GENERICS)))..."
	@$(GHDL) -e $(GHDL_FLAGS) $(TEST_TOP)
	@$(MKDIR) $(dir $(abspath $(TEST_LOG)))
	@$(GHDL) -r $(GHDL_FLAGS) $(TEST_TOP) $(GHDL_TEST_FLAGS) \
	    $(addprefix -g,$(TEST_GENERICS)) \
	    $(if $(strip $(TEST_TIME)),--stop-time=$(strip $(TEST_TIME))) \
	    $(GHDL_SIM_FLAGS) \
	    > "$(abspath $(TEST_LOG))" 2>&1; rc=$$?; \
	cat "$(abspath $(TEST_LOG))"; \
	if [ $$rc -ne 0 ] && [ "$(strip $(TEST_CHECK))" != "0" ]; then \
	    echo "[GHDL] FAILED — the simulation exited $$rc."; \
	    exit $$rc; \
	fi
	$(call _test_verdict,GHDL)

# ── Simulation ────────────────────────────────────────────────────────────────
simulate: elaborate
	@echo "[GHDL] Simulating '$(GHDL_TOP)'..."
	$(GHDL) -r $(GHDL_FLAGS) $(GHDL_TOP) \
	    --vcd=$(BUILD_DIR)/$(PROJECT_NAME).vcd \
	    $(GHDL_SIM_FLAGS)
	@echo "[GHDL] VCD written to $(BUILD_DIR)/$(PROJECT_NAME).vcd"

$(BUILD_DIR)/$(PROJECT_NAME): simulate

$(BUILD_DIR):
	$(MKDIR) $@
