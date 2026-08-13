# ==============================================================================
# vivado.mk — Xilinx Vivado toolchain rules
#
# The build is Non-Project Mode: sources are read, implemented and exported
# inside one in-memory Vivado session and no .xpr is written. A project is
# still available, but only to READ — see "The project is for reading" below.
#
# Build targets (Non-Project, in-memory):
#   synth       synthesis only, leaves post_synth.dcp
#   impl        synthesis + implementation, leaves post_route.dcp
#   bitstream   the above + .bit                                  (also 'all')
#   xsa         the above + hardware platform export for Vitis
#
# Reading and block-design authoring (.xpr):
#   project     build a browsable project from the same sources
#   gui         open the newest checkpoint in the IDE
#   project-gui open the browsable project in the IDE
#   bd-draft    create the editable block-design project
#   bd-gui      open that project in the IDE
#   bd-export   write the block design back out as versioned Tcl
#
# Simulation, software, hardware:
#   sim / sim-gui                 XSim behavioural simulation
#   vitis-platform / -apps / -run bare-metal software on the exported platform
#   program                       load the bitstream over JTAG
#
# ── The project is for reading ────────────────────────────────────────────────
# Nothing authored in the IDE survives, because nothing here builds from a
# project. The single sanctioned round trip is the block design:
#
#   make bd-draft   →  edit and SAVE in the IDE  →  make bd-export  →  commit
#
# The exported .tcl is the versioned artefact; the project that produced it is
# disposable. That export can express everything IP Integrator can — interface
# connections, address assignment, automation, hierarchies — none of which the
# VIVADO_BD_* bootstrap keys below can reach.
#
# ── Compilation order ─────────────────────────────────────────────────────────
# Vivado reads files in the order given and applies the same dependency rules
# as any VHDL tool. That order comes from per-directory .compile_order files
# (Layer 2) or VHDL_SRCS_DIR in project.mk (Layer 1). Non-Project Mode has no
# update_compile_order to fall back on, which makes the explicit order the
# contract rather than a safety net.
# ==============================================================================

# ── Layout ────────────────────────────────────────────────────────────────────
# VIVADO_OUT is also the working directory of every in-memory run: Vivado
# writes an in-memory project's output products (.gen/, .srcs/, .Xil/) into the
# current directory, so the recipes cd into it rather than litter the repo root.
VIVADO_OUT      := $(BUILD_DIR)/nonproject
VIVADO_PROJDIR  := $(abspath $(BUILD_DIR)/vivado_proj)
VIVADO_PARAMS   := $(BUILD_DIR)/vivado_params.tcl
VIVADO_SCRIPTS  := $(TEMPLATE_DIR)scripts
VIVADO_ENGINE   := $(VIVADO_SCRIPTS)/vivado_nonproject.tcl
VIVADO_PROJ_TCL := $(VIVADO_SCRIPTS)/vivado_project.tcl

VIVADO_BIT      := $(VIVADO_OUT)/$(VIVADO_TOP).bit
# Hardware platform handed to Vitis. Overridable so a project can publish it
# somewhere its software build expects.
VIVADO_XSA      ?= $(VIVADO_OUT)/$(VIVADO_TOP).xsa
VIVADO_DCP_ROUTE := $(VIVADO_OUT)/post_route.dcp
VIVADO_DCP_SYNTH := $(VIVADO_OUT)/post_synth.dcp

VIVADO_FLAGS    := -mode batch -notrace

# ── Board files (optional) ────────────────────────────────────────────────────
# A board part supplies presets a bare part number cannot: DDR timing and MIO
# assignments for a Zynq PS, pin maps, interface definitions. Third-party
# boards (Digilent et al.) are not shipped with Vivado, so VIVADO_BOARD_REPO
# points at a vendored copy — keeping it in the project means a fresh clone
# builds without modifying the Vivado installation.
#   VIVADO_BOARD_REPO := vivado/board_files
#   VIVADO_BOARD_PART := digilentinc.com:arty-z7-20:part0:1.1
VIVADO_BOARD_REPO ?=
VIVADO_BOARD_PART ?=

# ── VHDL standard ─────────────────────────────────────────────────────────────
# VHDL-2008 for every source by default. List the exceptions in VIVADO_VHDL93.
# The usual reason for an exception is IP Integrator: the top file of an RTL
# module reference may not be VHDL-2008 (ERROR [filemgmt 56-195]), so a thin
# wrapper is read as VHDL-93 while the core it wraps stays 2008.
VIVADO_VHDL_STD ?= 2008
VIVADO_VHDL93   ?=

# ── Simulation-only sources ───────────────────────────────────────────────────
# Files listed here are never handed to synthesis. Testbenches are the obvious
# case. The one that bites is a second architecture of a synthesizable entity
# (e.g. a TDD stub): read as a synthesis source, Vivado binds whichever
# architecture was analysed LAST, so a dead-bus stub can be synthesized in
# place of the real core — clean build log, dead hardware.
VIVADO_SIM_SRCS ?=

# ── Top-level generics ────────────────────────────────────────────────────────
#   VIVADO_GENERICS := G_VERSION=32'h00010001 G_BLINK_DIV_RST=125000000
VIVADO_GENERICS ?=

# ── IP (create_ip) ────────────────────────────────────────────────────────────
# VIVADO_IP lists instance (module) names; per instance:
#   VIVADO_IP_<name>_VLNV   := xilinx.com:ip:jtag_axi:1.2
#   VIVADO_IP_<name>_CONFIG := CONFIG.PROTOCOL=2 CONFIG.M_AXI_ADDR_WIDTH=32
#   VIVADO_IP_<name>_PRESET := path/to/board/preset.xml   (expanded first)
# Each is generated in context, so the design's own synthesis compiles it.
VIVADO_IP ?=

# ── Block design ──────────────────────────────────────────────────────────────
# VIVADO_BD_TCL is the versioned write_bd_tcl export and the source of truth.
# When the file exists, the build replays it and every VIVADO_BD_* key below is
# ignored. When it does not, the design is built from those keys — the
# bootstrap path, which exists so a processor-only handoff design works before
# anyone has opened the IDE.
#
# The reason a block design is worth having at all is write_hw_platform: it
# derives its .hwh hardware handoff from a block design, and a pure-RTL export
# gives Vitis a bitstream with no address map and no ps7_init — no bare-metal
# platform, no FSBL.
#
#   VIVADO_BD           block design name
#   VIVADO_BD_TCL       versioned export; canonical once it exists
#   VIVADO_BD_CELLS     bootstrap cells; each reuses VIVADO_IP_<cell>_VLNV,
#                       _PRESET and _CONFIG, exactly like a create_ip IP
#   VIVADO_BD_EXT_INTF  interface pins to expose, e.g. ps7_0/M_AXI_GP0
#   VIVADO_BD_EXT_PINS  scalar pins to expose, e.g. ps7_0/FCLK_CLK0
#   VIVADO_BD_NETS      internal connections as a=b pin pairs
#   VIVADO_BD_INTF_FREQ external interface clock rates, as port=hz. An external
#                       port does not inherit the rate of the pin it was made
#                       from, and validate_bd_design fails on the mismatch.
VIVADO_BD           ?=
VIVADO_BD_TCL       ?=
VIVADO_BD_CELLS     ?=
VIVADO_BD_EXT_INTF  ?=
VIVADO_BD_EXT_PINS  ?=
VIVADO_BD_NETS      ?=
VIVADO_BD_INTF_FREQ ?=

# ── ELF association (soft-core processors) ────────────────────────────────────
# Embeds compiled software in block RAM at bitstream time. MicroBlaze only — a
# Zynq PS loads from DDR/QSPI and needs nothing here.
#   VIVADO_ELF               := sw/hello.elf
#   VIVADO_ELF_<file>_REF    := microblaze_0
VIVADO_ELF ?=

# ── Implementation strategy ───────────────────────────────────────────────────
# Default directives everywhere; escalate per step when timing actually bites.
# Explore-class directives cost real build time on every run, so they are opt-in.
#   VIVADO_PHYS_OPT_DIRECTIVE := AggressiveExplore
#   VIVADO_PHYS_OPT_ON_WNS    := 1   run it only when placement missed timing
VIVADO_SYNTH_DIRECTIVE    ?=
VIVADO_OPT_DIRECTIVE      ?= Default
VIVADO_PLACE_DIRECTIVE    ?= Default
VIVADO_ROUTE_DIRECTIVE    ?= Default
VIVADO_PHYS_OPT_DIRECTIVE ?=
VIVADO_PHYS_OPT_ON_WNS    ?= 0
VIVADO_REPORTS            ?= 1
VIVADO_MAX_THREADS        ?=

# ── Simulation settings (XSim standalone flow: xvhdl → xelab → xsim) ──────────
VIVADO_SIM_TOP ?= $(VIVADO_TOP)
XVHDL          := xvhdl
XELAB          := xelab
XSIM           := xsim
XVHDL_FLAGS    ?= --2008
XELAB_FLAGS    ?= -debug typical
XSIM_DIR       := $(BUILD_DIR)/xsim
XSIM_SNAPSHOT  := $(VIVADO_SIM_TOP)_sim

# ── Derived source sets ───────────────────────────────────────────────────────
_vivado_synth_vhdl = $(filter-out $(VIVADO_SIM_SRCS),$(VHDL_SRCS))
_vivado_synth_v    = $(filter-out $(VIVADO_SIM_SRCS),$(V_SRCS))

# ── Tcl list helpers ──────────────────────────────────────────────────────────
# Each element is braced individually so Tcl takes it literally — paths and
# values survive without further escaping.
_tcl_files = $(foreach f,$(1),{$(abspath $(f))})
_tcl_words = $(foreach w,$(1),{$(w)})

# Board presets. Vivado's own CONFIG.PCW_IMPORT_BOARD_PRESET does nothing on an
# IP made with create_ip outside IP Integrator — accepted silently, applies no
# parameters (probed on 2021.2) — so the preset's parameters are expanded here
# and emitted BEFORE _CONFIG, letting a project take the vendor's whole preset
# and still override individual values.
#
# The IP name handed to the script comes from the VLNV's third field, since a
# preset file carries one preset per IP and the right block must be selected.
_vivado_preset_ipname = $(word 3,$(subst :, ,$(VIVADO_IP_$(1)_VLNV)))
_vivado_preset_dict   = $(if $(strip $(PRESET_SCRIPT)),\
    $(shell $(PRESET_SCRIPT) $(VIVADO_IP_$(1)_PRESET) $(call _vivado_preset_ipname,$(1))),\
    $(error VIVADO_IP_$(1)_PRESET is set but no preset script exists for $(HOST_OS)))

# Full CONFIG list for an IP or BD cell: preset first, explicit CONFIG second.
_vivado_cfg = $(if $(strip $(VIVADO_IP_$(1)_PRESET)),$(call _vivado_preset_dict,$(1)) )$(subst =, ,$(VIVADO_IP_$(1)_CONFIG))

.PHONY: all params synth impl bitstream xsa \
        project project-gui gui bd-draft bd-gui bd-export \
        sim sim-gui sim-elab vitis-platform vitis-apps vitis-run program

all: bitstream

$(BUILD_DIR) $(VIVADO_OUT) $(XSIM_DIR):
	$(MKDIR) $@

# ── Parameter file ────────────────────────────────────────────────────────────
# The only generated Tcl. It carries data, never flow: the flow lives in
# $(VIVADO_SCRIPTS)/, committed and reviewable on its own.
#
# Regenerated on every invocation — project.mk values and $(wildcard) source
# lists both change without any file this could depend on changing.
params: | $(VIVADO_OUT)
	@echo "[VIVADO] Writing parameters → $(VIVADO_PARAMS)"
	@( \
	echo "# Generated by vivado.mk — do not edit."; \
	echo "set ::p(part)   {$(VIVADO_PART)}"; \
	echo "set ::p(top)    {$(VIVADO_TOP)}"; \
	echo "set ::p(outdir) {$(abspath $(VIVADO_OUT))}"; \
	echo "set ::p(proj_name) {$(PROJECT_NAME)}"; \
	echo "set ::p(proj_dir)  {$(VIVADO_PROJDIR)}"; \
	echo "set ::p(target_language) {VHDL}"; \
	$(if $(strip $(VIVADO_BOARD_REPO)),echo "set ::p(board_repo) {$(abspath $(VIVADO_BOARD_REPO))}";) \
	$(if $(strip $(VIVADO_BOARD_PART)),echo "set ::p(board_part) {$(VIVADO_BOARD_PART)}";) \
	echo "set ::p(vhdl)    {$(call _tcl_files,$(_vivado_synth_vhdl))}"; \
	echo "set ::p(vhdl93)  {$(call _tcl_files,$(VIVADO_VHDL93))}"; \
	echo "set ::p(verilog) {$(call _tcl_files,$(_vivado_synth_v))}"; \
	echo "set ::p(xdc)     {$(call _tcl_files,$(VIVADO_XDC))}"; \
	echo "set ::p(generics) {$(call _tcl_words,$(VIVADO_GENERICS))}"; \
	echo "set ::p(ip) {$(call _tcl_words,$(VIVADO_IP))}"; \
	$(foreach ip,$(VIVADO_IP),\
	    echo "set ::p(ip,$(ip),vlnv)   {$(VIVADO_IP_$(ip)_VLNV)}"; \
	    echo "set ::p(ip,$(ip),config) {$(call _vivado_cfg,$(ip))}";) \
	$(if $(strip $(VIVADO_BD)),\
	    echo "set ::p(bd_name) {$(VIVADO_BD)}"; \
	    $(if $(strip $(VIVADO_BD_TCL)),echo "set ::p(bd_export) {$(abspath $(VIVADO_BD_TCL))}";) \
	    $(if $(wildcard $(VIVADO_BD_TCL)),echo "set ::p(bd_tcl) {$(abspath $(VIVADO_BD_TCL))}";) \
	    echo "set ::p(bd_cells) {$(call _tcl_words,$(VIVADO_BD_CELLS))}"; \
	    $(foreach c,$(VIVADO_BD_CELLS),\
	        echo "set ::p(bd,$(c),vlnv)   {$(VIVADO_IP_$(c)_VLNV)}"; \
	        echo "set ::p(bd,$(c),config) {$(call _vivado_cfg,$(c))}";) \
	    echo "set ::p(bd_ext_intf) {$(call _tcl_words,$(VIVADO_BD_EXT_INTF))}"; \
	    echo "set ::p(bd_ext_pins) {$(call _tcl_words,$(VIVADO_BD_EXT_PINS))}"; \
	    echo "set ::p(bd_nets) {$(foreach n,$(VIVADO_BD_NETS),$(call _tcl_words,$(subst =, ,$(n))))}"; \
	    echo "set ::p(bd_intf_freq) {$(foreach f,$(VIVADO_BD_INTF_FREQ),$(call _tcl_words,$(subst =, ,$(f))))}";) \
	$(if $(strip $(VIVADO_ELF)),\
	    echo "set ::p(elf) {$(call _tcl_files,$(VIVADO_ELF))}"; \
	    $(foreach e,$(VIVADO_ELF),\
	        echo "set ::p(elf,$(abspath $(e)),ref) {$(VIVADO_ELF_$(notdir $(e))_REF)}";)) \
	$(if $(strip $(VIVADO_SYNTH_DIRECTIVE)),echo "set ::p(synth_directive) {$(VIVADO_SYNTH_DIRECTIVE)}";) \
	echo "set ::p(opt_directive)   {$(VIVADO_OPT_DIRECTIVE)}"; \
	echo "set ::p(place_directive) {$(VIVADO_PLACE_DIRECTIVE)}"; \
	echo "set ::p(route_directive) {$(VIVADO_ROUTE_DIRECTIVE)}"; \
	echo "set ::p(phys_opt_directive) {$(VIVADO_PHYS_OPT_DIRECTIVE)}"; \
	echo "set ::p(phys_opt_on_wns)    {$(VIVADO_PHYS_OPT_ON_WNS)}"; \
	echo "set ::p(reports) {$(VIVADO_REPORTS)}"; \
	$(if $(strip $(VIVADO_MAX_THREADS)),echo "set ::p(max_threads) {$(VIVADO_MAX_THREADS)}";) \
	) > $(VIVADO_PARAMS)

# ── Non-Project build ─────────────────────────────────────────────────────────
# One Vivado invocation per target, always the full chain: an in-memory design
# does not outlive the process, so there is nothing to hand to a second run.
# This is also why the old double-synthesis failure mode cannot recur — there
# is no generated script that a later target can append to and re-source.
define _vivado_run
	cd $(VIVADO_OUT) && $(VIVADO) $(VIVADO_FLAGS) \
	    -log vivado_$(1).log -journal vivado_$(1).jou \
	    -source $(abspath $(VIVADO_ENGINE)) \
	    -tclargs -params $(abspath $(VIVADO_PARAMS)) -stage $(1)
endef

synth: params
	@echo "[VIVADO] Synthesis (non-project)..."
	$(call _vivado_run,synth)

impl: params
	@echo "[VIVADO] Synthesis + implementation (non-project)..."
	$(call _vivado_run,impl)

bitstream: params
	@echo "[VIVADO] Full build to bitstream (non-project)..."
	$(call _vivado_run,bitstream)
	@test -f "$(VIVADO_BIT)" || { echo "[VIVADO] ERROR: no bitstream at $(VIVADO_BIT)"; exit 1; }
	@echo "[VIVADO] Bitstream ready: $(VIVADO_BIT)"

# ps7_init.tcl is generated among the block design's output products. It is
# copied out because the in-tree path moves whenever the design is restructured.
xsa: params
	@echo "[VIVADO] Full build + hardware platform export (non-project)..."
	$(call _vivado_run,xsa)
	@test -f "$(VIVADO_XSA)" || { echo "[VIVADO] ERROR: no XSA at $(VIVADO_XSA)"; exit 1; }
	@echo "[VIVADO] Hardware platform ready: $(VIVADO_XSA)"
	@ps7=$$(find $(VIVADO_OUT) -name ps7_init.tcl 2>$(NULL) | head -1); \
	if [ -n "$$ps7" ]; then \
	    cp "$$ps7" $(VITIS_PS_INIT); \
	    echo "[VIVADO] PS init script: $(VITIS_PS_INIT)"; \
	fi

# ── Reading: checkpoints and the browsable project ────────────────────────────
# Checkpoints are the native way to inspect a non-project build — the routed
# design opens with its constraints, timing and placement intact.
gui:
	@if [ -f "$(VIVADO_DCP_ROUTE)" ]; then \
	    echo "[VIVADO] Opening $(VIVADO_DCP_ROUTE)..."; \
	    $(VIVADO) -mode gui $(VIVADO_DCP_ROUTE) & \
	elif [ -f "$(VIVADO_DCP_SYNTH)" ]; then \
	    echo "[VIVADO] Opening $(VIVADO_DCP_SYNTH)..."; \
	    $(VIVADO) -mode gui $(VIVADO_DCP_SYNTH) & \
	else \
	    echo "[VIVADO] ERROR: no checkpoint yet. Run 'make impl' or 'make bitstream' first."; \
	    exit 1; \
	fi

# A .xpr built from the same sources, for browsing hierarchy, schematics and IP
# dialogs. Never built from. FORCE=1 recreates it, discarding IDE edits.
project: params
	@echo "[VIVADO] Creating inspection project..."
	cd $(BUILD_DIR) && $(VIVADO) $(VIVADO_FLAGS) \
	    -log vivado_project.log -journal vivado_project.jou \
	    -source $(abspath $(VIVADO_PROJ_TCL)) \
	    -tclargs -params $(abspath $(VIVADO_PARAMS)) -mode project $(if $(FORCE),-force)

project-gui:
	@test -f "$(VIVADO_PROJDIR)/$(PROJECT_NAME).xpr" || { \
	    echo "[VIVADO] ERROR: no project. Run 'make project' first."; exit 1; }
	@echo "[VIVADO] Opening $(VIVADO_PROJDIR)/$(PROJECT_NAME).xpr (read only — nothing here is built)..."
	$(VIVADO) -mode gui $(VIVADO_PROJDIR)/$(PROJECT_NAME).xpr &

# ── Block design round trip ───────────────────────────────────────────────────
bd-draft: params
	@test -n "$(strip $(VIVADO_BD))" || { echo "[VIVADO] ERROR: VIVADO_BD is not set"; exit 1; }
	@test -n "$(strip $(VIVADO_BD_TCL))" || { \
	    echo "[VIVADO] ERROR: VIVADO_BD_TCL is not set — there is nowhere to export to."; exit 1; }
	@echo "[VIVADO] Creating block-design draft project..."
	cd $(BUILD_DIR) && $(VIVADO) $(VIVADO_FLAGS) \
	    -log vivado_bd_draft.log -journal vivado_bd_draft.jou \
	    -source $(abspath $(VIVADO_PROJ_TCL)) \
	    -tclargs -params $(abspath $(VIVADO_PARAMS)) -mode bd-draft $(if $(FORCE),-force)

bd-gui: project-gui

bd-export: params
	@test -n "$(strip $(VIVADO_BD_TCL))" || { echo "[VIVADO] ERROR: VIVADO_BD_TCL is not set"; exit 1; }
	@echo "[VIVADO] Exporting block design → $(VIVADO_BD_TCL)"
	cd $(BUILD_DIR) && $(VIVADO) $(VIVADO_FLAGS) \
	    -log vivado_bd_export.log -journal vivado_bd_export.jou \
	    -source $(abspath $(VIVADO_PROJ_TCL)) \
	    -tclargs -params $(abspath $(VIVADO_PARAMS)) -mode bd-export
	@test -f "$(VIVADO_BD_TCL)" || { echo "[VIVADO] ERROR: nothing written to $(VIVADO_BD_TCL)"; exit 1; }
	@echo "[VIVADO] Commit $(VIVADO_BD_TCL) — the build reads it from now on."

# ── Simulation ────────────────────────────────────────────────────────────────
# XSim writes its work library (xsim.dir) and logs into the current directory,
# so every step runs inside $(XSIM_DIR) with absolute source paths. Independent
# of both flows — no project and no in-memory design involved.
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

# ── Vitis: bare-metal software on the exported platform ───────────────────────
# Consumes VIVADO_XSA. Three targets, deliberately separate because the first is
# slow and rarely changes while the third runs constantly:
#   vitis-platform  create + generate the hardware platform (and its BSP)
#   vitis-apps      create/import/build each app in VITIS_APPS
#   vitis-run       reset, init the PS, load the bitstream, download and run
#
# XSCT is not on PATH under Vivado's settings64.sh; point at it explicitly:
#   XSCT := /tools/Xilinx/Vitis/2021.2/bin/xsct
XSCT           ?= xsct
VITIS_WS       ?= $(BUILD_DIR)/vitis_ws
VITIS_PLATFORM ?= $(VIVADO_TOP)_plat
VITIS_PROC     ?= ps7_cortexa9_0
VITIS_OS       ?= standalone
VITIS_DOMAIN   ?= standalone_domain
VITIS_APPS     ?=
VITIS_RUN_APP  ?= $(firstword $(VITIS_APPS))

VITIS_PLATFORM_TCL := $(BUILD_DIR)/vitis_platform.tcl
VITIS_APPS_TCL     := $(BUILD_DIR)/vitis_apps.tcl
VITIS_RUN_TCL      := $(BUILD_DIR)/vitis_run.tcl
VITIS_PS_INIT      := $(BUILD_DIR)/ps7_init.tcl

vitis-platform: | $(BUILD_DIR)
	@test -f "$(VIVADO_XSA)" || { \
	    echo "[VITIS] ERROR: no hardware platform at $(VIVADO_XSA)"; \
	    echo "[VITIS] Run 'make xsa' first."; \
	    exit 1; \
	}
	@echo "[VITIS] Generating platform script → $(VITIS_PLATFORM_TCL)"
	@( \
	echo "setws $(abspath $(VITIS_WS))"; \
	echo "platform create -name $(VITIS_PLATFORM) -hw $(abspath $(VIVADO_XSA)) -proc $(VITIS_PROC) -os $(VITIS_OS)"; \
	echo "platform generate"; \
	) > $(VITIS_PLATFORM_TCL)
	@echo "[VITIS] Building platform $(VITIS_PLATFORM)..."
	$(XSCT) $(VITIS_PLATFORM_TCL)

vitis-apps: | $(BUILD_DIR)
	@test -n "$(strip $(VITIS_APPS))" || { echo "[VITIS] ERROR: VITIS_APPS is empty"; exit 1; }
	@echo "[VITIS] Generating app script → $(VITIS_APPS_TCL)"
	@( \
	echo "setws $(abspath $(VITIS_WS))"; \
	$(foreach a,$(VITIS_APPS),\
	    echo "catch { app create -name $(a) -platform $(VITIS_PLATFORM) -domain $(VITIS_DOMAIN) -template {Empty Application(C)} }"; \
	    echo "importsources -name $(a) -path $(abspath $(VITIS_APP_$(a)_SRC))"; \
	    echo "app build -name $(a)";) \
	) > $(VITIS_APPS_TCL)
	@echo "[VITIS] Building app(s): $(VITIS_APPS)"
	$(XSCT) $(VITIS_APPS_TCL)

# The rules encoded below were each learned by breaking them:
#   'rst -system' on the APU, then halt core 0 — a plain 'stop' leaves the MMU
#     enabled with the running app's translation table and 'dow' faults with
#     "MMU page translation fault"; 'rst -processor' alone is not enough either,
#     since the second core keeps running and the DAP can wedge into
#     "AHB AP transaction error"
#   ps7_init before loading the PL — FCLK comes from the PS PLLs
#   the bitstream goes in after ps7_post_config, not before
#   end with 'con' — a halted A9 eventually wedges the DAP into
#     "AHB AP transaction error", recoverable only by replugging the cable
vitis-run: | $(BUILD_DIR)
	@test -f "$(VIVADO_BIT)" || { echo "[VITIS] ERROR: no bitstream at $(VIVADO_BIT)"; exit 1; }
	@test -n "$(strip $(VITIS_RUN_APP))" || { echo "[VITIS] ERROR: VITIS_RUN_APP is empty"; exit 1; }
	@test -f "$(VITIS_PS_INIT)" || { \
	    echo "[VITIS] ERROR: no PS init script at $(VITIS_PS_INIT)"; \
	    echo "[VITIS] 'make xsa' copies it out of the build tree."; \
	    exit 1; \
	}
	@echo "[VITIS] Generating run script → $(VITIS_RUN_TCL)"
	@( \
	echo "connect"; \
	echo "after 3000"; \
	echo 'targets -set -filter {name =~ "*Cortex-A9*#1"}'; \
	echo "stop"; \
	echo 'targets -set -filter {name =~ "*Cortex-A9*#0"}'; \
	echo "rst -processor"; \
	echo "after 1000"; \
	echo "source $(abspath $(VITIS_PS_INIT))"; \
	echo "ps7_init"; \
	echo "ps7_post_config"; \
	echo "fpga -file $(abspath $(VIVADO_BIT))"; \
	echo "dow $(abspath $(VITIS_WS))/$(VITIS_RUN_APP)/Debug/$(VITIS_RUN_APP).elf"; \
	echo "con"; \
	) > $(VITIS_RUN_TCL)
	@echo "[VITIS] Running $(VITIS_RUN_APP) on hardware..."
	$(XSCT) $(VITIS_RUN_TCL)

# ── Program device ────────────────────────────────────────────────────────────
# Optional overrides:
#   VIVADO_HW_SERVER  hw_server URL, e.g. localhost:3121. Empty = local server.
#   VIVADO_HW_TARGET  target pattern when several cables are attached.
#   VIVADO_HW_DEVICE  device pattern. Empty picks the first PROGRAMMABLE device
#                     — see the arm_dap note below, which is why this is not
#                     simply "the first device in the chain".
VIVADO_PROG_TCL  := $(BUILD_DIR)/vivado_program.tcl
VIVADO_HW_SERVER ?=
VIVADO_HW_TARGET ?=
VIVADO_HW_DEVICE ?=

program: | $(BUILD_DIR)
	@test -f "$(VIVADO_BIT)" || { \
	    echo "[VIVADO] ERROR: no bitstream at $(VIVADO_BIT)"; \
	    echo "[VIVADO] Run 'make bitstream' first."; \
	    exit 1; \
	}
	@echo "[VIVADO] Generating program script → $(VIVADO_PROG_TCL)"
	@( \
	echo "open_hw_manager"; \
	echo "connect_hw_server$(if $(strip $(VIVADO_HW_SERVER)), -url $(VIVADO_HW_SERVER),)"; \
	echo "open_hw_target$(if $(strip $(VIVADO_HW_TARGET)), {$(VIVADO_HW_TARGET)},)"; \
	$(if $(strip $(VIVADO_HW_DEVICE)),\
	    echo "set dev [lindex [get_hw_devices $(VIVADO_HW_DEVICE)] 0]";,\
	    echo "set dev {}"; \
	    echo "foreach d [get_hw_devices] {"; \
	    echo "    if {![string match {arm_dap*} \$$d]} { set dev \$$d ; break }"; \
	    echo "}";) \
	echo "if {\$$dev eq {}} { puts \"ERROR: no programmable device in the JTAG chain\" ; exit 1 }"; \
	echo "puts \"VIVADO: target device \$$dev\""; \
	echo "current_hw_device \$$dev"; \
	echo "refresh_hw_device -update_hw_probes false \$$dev"; \
	echo "set_property PROGRAM.FILE {$(abspath $(VIVADO_BIT))} \$$dev"; \
	echo "program_hw_devices \$$dev"; \
	echo "refresh_hw_device \$$dev"; \
	echo "close_hw_manager"; \
	) > $(VIVADO_PROG_TCL)
	@echo "[VIVADO] Programming device..."
	$(VIVADO) $(VIVADO_FLAGS) -source $(VIVADO_PROG_TCL)

$(BUILD_DIR)/$(PROJECT_NAME): bitstream
