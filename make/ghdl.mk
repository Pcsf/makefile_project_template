# ==============================================================================
# ghdl.mk — GHDL VHDL simulator toolchain rules
# Handles: .vhd/.vhdl → analysis → elaboration → simulation (VCD output)
#
# ── Compilation order strategy ────────────────────────────────────────────────
# VHDL requires that packages and entities are analysed before any design unit
# that references them.  Three layers of defence are applied:
#
#   Layer 1 – VHDL_SRCS global override in project.mk (manual, full control)
#   Layer 2 – per-directory .compile_order files (semi-automatic, persistent)
#   Layer 3 – silent pre-pass below (fully automatic, handles most cases)
#
# The pre-pass analyses every file once, ignoring errors.  Any file that
# succeeds pre-populates the work library.  The real pass then finds all
# previously-analysed units available and compiles in declared order.
# Circular dependencies (a design error) are the only case not handled.
# ==============================================================================

GHDL_WORKDIR := $(BUILD_DIR)/ghdl_work
GHDL_FLAGS   += --std=$(GHDL_STD) --workdir=$(GHDL_WORKDIR)

.PHONY: all analyze elaborate simulate

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
