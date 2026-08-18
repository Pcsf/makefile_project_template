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

GHDL_WORKDIR := $(BUILD_DIR)/ghdl_work
GHDL_FLAGS   += --std=$(GHDL_STD) --workdir=$(GHDL_WORKDIR)

.PHONY: all analyze elaborate simulate _help_ghdl

# Listed by 'make help' — see the TOOLCHAIN_HELP_TARGET hook in common.mk.
TOOLCHAIN_HELP_TARGET := _help_ghdl

_help_ghdl:
	@echo ""
	@echo "  GHDL targets:"
	@echo "    analyze    Analyse the VHDL sources"
	@echo "    elaborate  Elaborate GHDL_TOP"
	@echo "    simulate   Run the simulation — this is what 'all' builds"

all: simulate

$(GHDL_WORKDIR):
	$(MKDIR) $(GHDL_WORKDIR)

# ── Analysis ──────────────────────────────────────────────────────────────────
analyze: | $(GHDL_WORKDIR)
	@echo "[GHDL] Analysing $(words $(VHDL_SRCS)) VHDL file(s) (std=$(GHDL_STD))..."
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
