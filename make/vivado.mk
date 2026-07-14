# ==============================================================================
# vivado.mk — Xilinx Vivado toolchain rules
# Handles: VHDL / Verilog / SV + XDC constraints → synthesis → impl → bitstream
#
# Targets:
#   all / bitstream — full build: synthesis + implementation + bitstream
#   synth           — synthesis only
#   impl            — synthesis + implementation
#   sim             — XSim behavioural simulation, batch (run to completion)
#   sim-gui         — XSim behavioural simulation, waveform GUI
#   program         — program the bitstream onto the connected device
#
# ── Compilation order strategy ────────────────────────────────────────────────
# Vivado's read_vhdl in non-project (Tcl batch) mode processes files in the
# order they are listed — same dependency rules as any VHDL tool apply.
# VHDL_SRCS order is controlled by per-directory .compile_order files (Layer 2)
# or VHDL_SRCS_DIR in project.mk (Layer 1 — list directories in order).
#
# Note: Vivado's 'update_compile_order' reorders sources for VHDL-2008 based
# on its own analysis, but this is unreliable for older VHDL standards and
# for configurations / packages that span library boundaries.  Relying on
# explicit order (Layers 1/2) is safer.
# ==============================================================================

VIVADO_PROJDIR := $(BUILD_DIR)/vivado_proj
VIVADO_TCL     := $(BUILD_DIR)/vivado_build.tcl
VIVADO_BIT     := $(VIVADO_PROJDIR)/$(PROJECT_NAME).runs/impl_1/$(VIVADO_TOP).bit
VIVADO_FLAGS   := -mode batch -nojournal -nolog -quiet

# ── Simulation settings (XSim standalone flow: xvhdl → xelab → xsim) ──────────
# Simulation top-level entity — usually the testbench, not the synthesis top.
VIVADO_SIM_TOP ?= $(VIVADO_TOP)
XVHDL          := xvhdl
XELAB          := xelab
XSIM           := xsim
XVHDL_FLAGS    ?= --2008
# -debug typical keeps signal visibility for the waveform GUI
XELAB_FLAGS    ?= -debug typical
# Extra run-time options, e.g. generics: XELAB_FLAGS += -generic_top G_RED=true
XSIM_DIR       := $(BUILD_DIR)/xsim
XSIM_SNAPSHOT  := $(VIVADO_SIM_TOP)_sim

.PHONY: all tcl synth impl bitstream program sim sim-gui sim-elab

all: bitstream

$(BUILD_DIR) $(VIVADO_PROJDIR) $(XSIM_DIR):
	$(MKDIR) $@

# ── Simulation ────────────────────────────────────────────────────────────────
# XSim writes its work library (xsim.dir) and logs into the current directory,
# so every step runs inside $(XSIM_DIR) with absolute source paths.
sim-elab: | $(XSIM_DIR)
	@echo "[XSIM] Compiling VHDL sources..."
	cd $(XSIM_DIR) && $(XVHDL) $(XVHDL_FLAGS) $(abspath $(VHDL_SRCS))
	@echo "[XSIM] Elaborating $(VIVADO_SIM_TOP)..."
	cd $(XSIM_DIR) && $(XELAB) $(XELAB_FLAGS) -s $(XSIM_SNAPSHOT) work.$(VIVADO_SIM_TOP)

sim: sim-elab
	@echo "[XSIM] Running simulation (batch)..."
	cd $(XSIM_DIR) && $(XSIM) $(XSIM_SNAPSHOT) -runall

sim-gui: sim-elab
	@echo "[XSIM] Launching simulation GUI..."
	cd $(XSIM_DIR) && $(XSIM) $(XSIM_SNAPSHOT) -gui

# ── Generate Tcl build script ─────────────────────────────────────────────────
# VHDL files are added in VHDL_SRCS order (set by .compile_order / project.mk).
# update_compile_order is called as a safety net for VHDL-2008 projects; it
# does NOT reorder for older standards.
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
