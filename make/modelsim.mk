# ==============================================================================
# modelsim.mk — ModelSim / QuestaSim HDL simulator toolchain rules
# Handles: .vhd/.vhdl (.v/.sv Verilog) → compile → simulate
# ==============================================================================

VSIM_WORKDIR := $(BUILD_DIR)/modelsim_work

.PHONY: all compile simulate

all: simulate

$(VSIM_WORKDIR):
	$(MKDIR) $(VSIM_WORKDIR)

# ── Create / map work library ─────────────────────────────────────────────────
$(VSIM_WORKDIR)/$(VSIM_WORK)/_info: | $(VSIM_WORKDIR)
	@echo "[MSIM] Creating work library..."
	$(VLIB) $(VSIM_WORKDIR)/$(VSIM_WORK)
	$(VMAP) $(VSIM_WORK) $(VSIM_WORKDIR)/$(VSIM_WORK)

# ── Compile VHDL ─────────────────────────────────────────────────────────────
compile: $(VSIM_WORKDIR)/$(VSIM_WORK)/_info
ifneq ($(strip $(VHDL_SRCS)),)
	@echo "[MSIM] Compiling $(words $(VHDL_SRCS)) VHDL file(s)..."
	@$(foreach f,$(VHDL_SRCS),\
	    echo "  [VCOM] $(f)" && \
	    $(VCOM) -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	            -work $(VSIM_WORK) -$(GHDL_STD) $(f) || exit 1;)
endif
ifneq ($(strip $(V_SRCS)),)
	@echo "[MSIM] Compiling $(words $(V_SRCS)) Verilog/SV file(s)..."
	@$(foreach f,$(V_SRCS),\
	    echo "  [VLOG] $(f)" && \
	    $(VLOG) -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	            -work $(VSIM_WORK) $(f) || exit 1;)
endif

# ── Simulate ─────────────────────────────────────────────────────────────────
simulate: compile
	@echo "[MSIM] Simulating '$(VSIM_WORK).$(VSIM_TOP)'..."
	$(VSIM) -c $(VSIM_FLAGS) \
	    -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	    -do "run -all; quit -f" \
	    $(VSIM_WORK).$(VSIM_TOP)

$(BUILD_DIR)/$(PROJECT_NAME): simulate

$(BUILD_DIR):
	$(MKDIR) $@
