# ==============================================================================
# modelsim.mk — ModelSim / QuestaSim HDL simulator toolchain rules
# Handles: .vhd/.vhdl + .v/.sv → compile → simulate
#
# ── Compilation order strategy ────────────────────────────────────────────────
# Same three-layer defence as ghdl.mk:
#   Layer 1 – VHDL_SRCS_DIR in project.mk: directories in compilation order;
#              file lists within each directory remain auto-managed
#   Layer 2 – per-directory .compile_order files (created by 'make scan')
#   Layer 3 – silent pre-pass below (auto-handles most ordering issues)
#
# vcom fails fast on an unresolved reference but succeeds if the referenced
# unit is already in the work library from a previous run.  The pre-pass
# compiles as many files as possible so the real pass finds all dependencies.
# ==============================================================================

# ── Tool names ───────────────────────────────────────────────────────────────
# Defaulted rather than required. Without a default an unset variable expands to
# nothing and the recipe runs its own first flag as the command, which fails as
# "not found" and points at the flag rather than at the missing tool.
VSIM      ?= vsim
VCOM      ?= vcom
VLOG      ?= vlog
VLIB      ?= vlib
VMAP      ?= vmap
VSIM_WORK ?= work

VSIM_WORKDIR := $(BUILD_DIR)/modelsim_work
VHDL_LIB_COMPILE_TARGETS := $(addprefix compile-lib-,$(VHDL_LIBS))

# GHDL and vcom spell VHDL standards differently. Questa uses the full year
# for VHDL-2002/2008, while GHDL_STD is configured as 02/08.
VCOM_STD_FLAG := $(if $(filter 08,$(GHDL_STD)),-2008,$(if $(filter 00 02,$(GHDL_STD)),-2002,-$(GHDL_STD)))

.PHONY: all compile compile-vhdl-libs simulate sim sim-gui test test-compile test-run _help_modelsim $(VHDL_LIB_COMPILE_TARGETS)

# Listed by 'make help' — see the TOOLCHAIN_HELP_TARGET hook in common.mk.
TOOLCHAIN_HELP_TARGET := _help_modelsim

_help_modelsim:
	@echo ""
	@echo "  ModelSim targets:"
	@echo "    compile    Compile the sources into the work library"
	@echo "    simulate   Run VSIM_TOP in batch — this is what 'all' builds"
	@echo "    sim        Alias for simulate"
	@echo "    sim-gui    Open VSIM_TOP in the simulator GUI"
	@echo "    test       Run VSIM_TOP in batch and render a verdict"

all: simulate
sim: simulate

# ── The test verdict ──────────────────────────────────────────────────────────
# `simulate` is the developer-facing run. `test` is the machine-facing one, and
# its exit status is the verdict.
#
# The simulator's own status cannot supply that: the batch run ends in
# `quit -f`, which sets no exit code, so a run where every check failed and a
# clean run are indistinguishable by status. The transcript is therefore the
# source of truth, the same way it is for any runner that exits zero
# regardless of outcome.
#
# The default fail pattern is the simulator's own rendering of VHDL severities
# (`severity error` and `severity failure` print as `** Error:` and `** Failure:`),
# so a testbench using assert/report is covered without adopting a convention.
# A verification library that counts its own alerts and reports in a summary
# line raises no severity at all: declare that project's TEST_FAIL_PATTERN or
# TEST_PASS_PATTERN for it.
TEST_TOP          ?= $(VSIM_TOP)
TEST_LOG          ?= $(BUILD_DIR)/test_$(TEST_TOP).log
TEST_FAIL_PATTERN ?= \*\* (Error|Failure|Fatal):

TOOLCHAIN_HAS_TEST  := 1
TOOLCHAIN_HAS_CASES := 1

# One verdict run of TEST_TOP. TEST_GENERICS and TEST_TIME are the
# toolchain-neutral case settings described in common.mk: generics are applied
# at load time, and a time limit replaces `run -all`.
test-compile: compile

test-run: $(if $(strip $(TEST_COMPILED)),,compile)
	@echo "[MSIM] Testing '$(VSIM_WORK).$(TEST_TOP)'$(if $(strip $(TEST_GENERICS)), with $(strip $(TEST_GENERICS)))..."
	@$(MKDIR) $(dir $(abspath $(TEST_LOG)))
	@rm -f "$(abspath $(TEST_LOG))"
	@$(VSIM) -c $(VSIM_FLAGS) \
	    -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	    -l $(abspath $(TEST_LOG)) \
	    $(addprefix -g,$(TEST_GENERICS)) \
	    -do "$(if $(strip $(TEST_TIME)),run $(strip $(TEST_TIME)),run -all); quit -f" \
	    $(VSIM_WORK).$(TEST_TOP) > /dev/null 2>&1 || true
	@cat "$(abspath $(TEST_LOG))" 2>/dev/null || true
	$(call _test_verdict,MSIM)

$(VSIM_WORKDIR):
	$(MKDIR) $(VSIM_WORKDIR)

# ── Create / map work library ─────────────────────────────────────────────────
$(VSIM_WORKDIR)/$(VSIM_WORK)/_info: | $(VSIM_WORKDIR)
	@echo "[MSIM] Creating work library..."
	$(VLIB) $(VSIM_WORKDIR)/$(VSIM_WORK)
	cd $(VSIM_WORKDIR) && $(VMAP) -c
	$(VMAP) -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	    $(VSIM_WORK) $(abspath $(VSIM_WORKDIR)/$(VSIM_WORK))

# ── Named VHDL libraries ──────────────────────────────────────────────────────
define MSIM_VHDL_LIB_template
$$(VSIM_WORKDIR)/$(1)/_info: $$(VSIM_WORKDIR)/$$(VSIM_WORK)/_info
	@echo "[MSIM] Creating library '$(1)'..."
	$$(VLIB) $$(VSIM_WORKDIR)/$(1)
	$$(VMAP) -modelsimini $$(VSIM_WORKDIR)/modelsim.ini \
	    $(1) $$(abspath $$(VSIM_WORKDIR)/$(1))

compile-lib-$(1): $$(addprefix compile-lib-,$$(VHDL_LIB_$(1)_DEPS)) $$(VSIM_WORKDIR)/$(1)/_info
	@test -n "$$(strip $$(VHDL_LIB_$(1)_SRCS))" || { echo "[MSIM] No sources configured for VHDL library '$(1)'"; exit 1; }
	@echo "[MSIM] Compiling library '$(1)' ($$(words $$(VHDL_LIB_$(1)_SRCS)) file(s))..."
	@$$(foreach f,$$(VHDL_LIB_$(1)_SRCS),\
	    printf '  [VCOM:$(1)] %s\n' '$$(f)' && \
	    $$(VCOM) -modelsimini $$(VSIM_WORKDIR)/modelsim.ini \
	        -work $(1) $$(VCOM_STD_FLAG) $$(VHDL_LIB_$(1)_VCOM_FLAGS) $$(f) || \
	    { echo '[MSIM] FAILED on: $$(f) (library $(1))'; exit 1; };)
endef

$(foreach lib,$(VHDL_LIBS),$(eval $(call MSIM_VHDL_LIB_template,$(lib))))

compile-vhdl-libs: $(VHDL_LIB_COMPILE_TARGETS)

# ── Compile ───────────────────────────────────────────────────────────────────
compile: compile-vhdl-libs $(VSIM_WORKDIR)/$(VSIM_WORK)/_info
ifneq ($(strip $(VHDL_SRCS)),)
	@echo "[MSIM] VHDL pre-pass ($(words $(VHDL_SRCS)) file(s), errors silenced)..."
	@$(foreach f,$(VHDL_SRCS),\
	    $(VCOM) -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	            -work $(VSIM_WORK) $(VCOM_STD_FLAG) $(f) 2>/dev/null;) true
	@echo "[MSIM] VHDL final pass:"
	@$(foreach f,$(VHDL_SRCS),\
	    printf '  [VCOM] %s\n' '$(f)' && \
	    $(VCOM) -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	            -work $(VSIM_WORK) $(VCOM_STD_FLAG) $(f) || \
	    { echo '[MSIM] FAILED on: $(f)'; \
	      echo '[MSIM] Fix: check .compile_order or set VHDL_SRCS in project.mk'; \
	      exit 1; };)
endif
ifneq ($(strip $(V_SRCS)),)
	@echo "[MSIM] Verilog/SV pre-pass ($(words $(V_SRCS)) file(s), errors silenced)..."
	@$(foreach f,$(V_SRCS),\
	    $(VLOG) -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	            -work $(VSIM_WORK) $(f) 2>/dev/null;) true
	@echo "[MSIM] Verilog/SV final pass:"
	@$(foreach f,$(V_SRCS),\
	    printf '  [VLOG] %s\n' '$(f)' && \
	    $(VLOG) -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	            -work $(VSIM_WORK) $(f) || \
	    { echo '[MSIM] FAILED on: $(f)'; exit 1; };)
endif

# ── Simulate ─────────────────────────────────────────────────────────────────
simulate: compile
	@echo "[MSIM] Simulating '$(VSIM_WORK).$(VSIM_TOP)'..."
	$(VSIM) -c $(VSIM_FLAGS) \
	    -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	    -do "run -all; quit -f" \
	    $(VSIM_WORK).$(VSIM_TOP)

sim-gui: compile
	@echo "[MSIM] Opening '$(VSIM_WORK).$(VSIM_TOP)' in the simulator GUI..."
	$(VSIM) $(VSIM_FLAGS) \
	    -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	    $(VSIM_WORK).$(VSIM_TOP)

$(BUILD_DIR)/$(PROJECT_NAME): simulate

$(BUILD_DIR):
	$(MKDIR) $@
