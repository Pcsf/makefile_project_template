# ==============================================================================
# vivado.mk — Xilinx Vivado toolchain rules
# Handles: VHDL / Verilog / SV + XDC constraints → synthesis → impl → bitstream
# ==============================================================================

VIVADO_PROJDIR := $(BUILD_DIR)/vivado_proj
VIVADO_TCL     := $(BUILD_DIR)/vivado_build.tcl
VIVADO_BIT     := $(VIVADO_PROJDIR)/$(PROJECT_NAME).runs/impl_1/$(VIVADO_TOP).bit
VIVADO_FLAGS   := -mode batch -nojournal -nolog -quiet

.PHONY: all tcl synth impl bitstream program

all: bitstream

$(BUILD_DIR) $(VIVADO_PROJDIR):
	$(MKDIR) $@

# ── Generate Tcl build script ─────────────────────────────────────────────────
tcl: | $(BUILD_DIR)
	@echo "[VIVADO] Generating Tcl script → $(VIVADO_TCL)"
	@( \
	echo "create_project -force $(PROJECT_NAME) $(VIVADO_PROJDIR) -part $(VIVADO_PART)"; \
	$(foreach f,$(VHDL_SRCS),\
	    echo "read_vhdl -library xil_defaultlib {$(f)}";) \
	$(foreach f,$(V_SRCS),\
	    echo "read_verilog {$(f)}";) \
	$(foreach f,$(VIVADO_XDC),\
	    echo "read_xdc {$(f)}";) \
	echo "set_property top $(VIVADO_TOP) [current_fileset]"; \
	echo "update_compile_order -fileset sources_1"; \
	) > $(VIVADO_TCL)

# ── Synthesis ─────────────────────────────────────────────────────────────────
synth: tcl
	@echo "[VIVADO] Running synthesis..."
	@echo "launch_runs synth_1 -jobs 4" >> $(VIVADO_TCL)
	@echo "wait_on_run synth_1"         >> $(VIVADO_TCL)
	@echo "if {[get_property PROGRESS [get_runs synth_1]] ne {100%}} {exit 1}" >> $(VIVADO_TCL)
	$(VIVADO) $(VIVADO_FLAGS) -source $(VIVADO_TCL)

# ── Implementation ────────────────────────────────────────────────────────────
impl: synth
	@echo "[VIVADO] Running implementation..."
	@echo "launch_runs impl_1 -to_step write_bitstream -jobs 4" >> $(VIVADO_TCL)
	@echo "wait_on_run impl_1" >> $(VIVADO_TCL)
	@echo "if {[get_property PROGRESS [get_runs impl_1]] ne {100%}} {exit 1}" >> $(VIVADO_TCL)
	$(VIVADO) $(VIVADO_FLAGS) -source $(VIVADO_TCL)

# ── Bitstream ─────────────────────────────────────────────────────────────────
bitstream: impl
	@echo "[VIVADO] Bitstream ready: $(VIVADO_BIT)"

# ── Program device (optional) ─────────────────────────────────────────────────
program:
	@echo "[VIVADO] Programming device..."
	$(VIVADO) $(VIVADO_FLAGS) -source - <<'TCL'
	open_hw_manager
	connect_hw_server
	open_hw_target
	set_property PROGRAM.FILE {$(VIVADO_BIT)} [current_hw_device]
	program_hw_devices [current_hw_device]
	close_hw_manager
	TCL

$(BUILD_DIR)/$(PROJECT_NAME): bitstream

$(BUILD_DIR):
	$(MKDIR) $@
