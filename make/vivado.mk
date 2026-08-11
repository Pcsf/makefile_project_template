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

# ── Board files (optional) ────────────────────────────────────────────────────
# A board part supplies presets a bare part number cannot: DDR timing and MIO
# assignments for a Zynq PS, pin maps, interface definitions. Third-party
# boards (Digilent et al.) are not shipped with Vivado, so VIVADO_BOARD_REPO
# points at a vendored copy — keeping it in the project means a fresh clone
# builds without modifying the Vivado installation.
#   VIVADO_BOARD_REPO := vivado/board_files
#   VIVADO_BOARD_PART := digilentinc.com:arty-z7-20:part0:1.1
# NOTE: board.repoPaths must be set BEFORE create_project, which the generator
# below takes care of; setting it afterwards silently finds nothing.
VIVADO_BOARD_REPO ?=
VIVADO_BOARD_PART ?=

# ── VHDL standard ─────────────────────────────────────────────────────────────
# VHDL-2008 for every source by default. List the exceptions in VIVADO_VHDL93.
# The usual reason for an exception is IP Integrator: the top file of an RTL
# module reference may not be VHDL-2008 (ERROR [filemgmt 56-195]), so a thin
# wrapper gets built as VHDL-93 while the core it wraps stays 2008.
VIVADO_VHDL_STD ?= 2008
VIVADO_VHDL93   ?=

# ── Simulation-only sources ───────────────────────────────────────────────────
# Files listed here go to the sim_1 fileset ONLY; everything else in
# VHDL_SRCS/V_SRCS goes to sources_1 for synthesis. Testbenches are the obvious
# case. The one that bites is a second architecture of a synthesizable entity
# (e.g. a TDD stub): left in sources_1, Vivado binds whichever architecture was
# analysed LAST, so a dead-bus stub can be synthesized in place of the real
# core — clean build log, dead hardware.
VIVADO_SIM_SRCS ?=

# ── Top-level generics ────────────────────────────────────────────────────────
# Passed to the synthesis fileset, e.g.
#   VIVADO_GENERICS := G_VERSION=32'h00010001 G_BLINK_DIV_RST=125000000
VIVADO_GENERICS ?=

# ── IP ────────────────────────────────────────────────────────────────────────
# VIVADO_IP lists instance (module) names; per instance:
#   VIVADO_IP_<name>_VLNV   := xilinx.com:ip:jtag_axi:1.2
#   VIVADO_IP_<name>_CONFIG := CONFIG.PROTOCOL=2 CONFIG.M_AXI_ADDR_WIDTH=32
# Each is generated IN CONTEXT (generate_synth_checkpoint false). Out-of-context
# is Vivado's default and produces its checkpoint from a child run launched by
# launch_runs; a non-project flow that skips that gets the IP as an empty box:
#   ERROR [DRC INBB-3] ... has undefined contents and is considered a black box.
VIVADO_IP ?=

# Synthesis sources are everything except the simulation-only ones.
_vivado_synth_vhdl = $(filter-out $(VIVADO_SIM_SRCS),$(VHDL_SRCS))
_vivado_synth_v    = $(filter-out $(VIVADO_SIM_SRCS),$(V_SRCS))
_vivado_sim_only   = $(filter $(VIVADO_SIM_SRCS),$(VHDL_SRCS) $(V_SRCS))

# file_type for one VHDL file: VHDL-93 when listed in VIVADO_VHDL93, else the
# project default. Vivado spells the 2008 type "VHDL 2008" and plain 93 "VHDL".
_vivado_ftype = $(if $(filter $(1),$(VIVADO_VHDL93)),VHDL,VHDL $(VIVADO_VHDL_STD))

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
	$(if $(strip $(VIVADO_BOARD_REPO)),\
	    echo "set_param board.repoPaths [list $(abspath $(VIVADO_BOARD_REPO))]";) \
	echo "create_project -force $(PROJECT_NAME) $(VIVADO_PROJDIR) -part $(VIVADO_PART)"; \
	$(if $(strip $(VIVADO_BOARD_PART)),\
	    echo "set_property board_part $(VIVADO_BOARD_PART) [current_project]";) \
	echo "set_property target_language VHDL [current_project]"; \
	$(foreach f,$(_vivado_synth_vhdl),\
	    echo "read_vhdl -library xil_defaultlib {$(f)}"; \
	    echo "set_property file_type {$(call _vivado_ftype,$(f))} [get_files {$(f)}]";) \
	$(foreach f,$(_vivado_synth_v),\
	    echo "read_verilog {$(f)}";) \
	$(foreach f,$(_vivado_sim_only),\
	    echo "add_files -fileset sim_1 -norecurse {$(f)}"; \
	    echo "set_property file_type {$(call _vivado_ftype,$(f))} [get_files -of_objects [get_filesets sim_1] {$(f)}]";) \
	$(if $(strip $(VIVADO_SIM_TOP)),\
	    echo "set_property top $(VIVADO_SIM_TOP) [get_filesets sim_1]";) \
	$(foreach f,$(VIVADO_XDC),\
	    echo "read_xdc {$(f)}";) \
	$(foreach ip,$(VIVADO_IP),\
	    echo "create_ip -vlnv $(VIVADO_IP_$(ip)_VLNV) -module_name $(ip)"; \
	    $(if $(strip $(VIVADO_IP_$(ip)_CONFIG)),\
	        echo "set_property -dict [list $(subst =, ,$(VIVADO_IP_$(ip)_CONFIG))] [get_ips $(ip)]";) \
	    echo "set_property generate_synth_checkpoint false [get_files $(ip).xci]"; \
	    echo "generate_target all [get_files $(ip).xci]";) \
	echo "set_property top $(VIVADO_TOP) [current_fileset]"; \
	$(if $(strip $(VIVADO_GENERICS)),\
	    echo "set_property generic {$(VIVADO_GENERICS)} [current_fileset]";) \
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
