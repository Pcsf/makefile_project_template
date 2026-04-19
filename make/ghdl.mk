# ==============================================================================
# ghdl.mk — GHDL VHDL simulator toolchain rules
# Handles: .vhd/.vhdl → analysis → elaboration → simulation (VCD output)
# ==============================================================================

GHDL_WORKDIR := $(BUILD_DIR)/ghdl_work
GHDL_FLAGS   += --std=$(GHDL_STD) --workdir=$(GHDL_WORKDIR)

.PHONY: all analyze elaborate simulate

all: simulate

$(GHDL_WORKDIR):
	$(MKDIR) $(GHDL_WORKDIR)

# ── Analysis: parse and type-check all VHDL sources ──────────────────────────
analyze: | $(GHDL_WORKDIR)
	@echo "[GHDL] Analysing $(words $(VHDL_SRCS)) VHDL file(s)..."
	@$(foreach f,$(VHDL_SRCS),\
	    echo "  [GHDL-A] $(f)" && \
	    $(GHDL) -a $(GHDL_FLAGS) $(f) || exit 1;)

# ── Elaboration: build the simulation executable ──────────────────────────────
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

# Alias so 'all' has a concrete file target
$(BUILD_DIR)/$(PROJECT_NAME): simulate

$(BUILD_DIR):
	$(MKDIR) $@
