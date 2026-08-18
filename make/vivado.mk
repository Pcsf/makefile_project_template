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

# ── Tool names ───────────────────────────────────────────────────────────────
# Defaulted rather than required. Without a default an unset variable expands to
# nothing and the recipe runs its own first flag as the command, which fails as
# "not found" and points at the flag rather than at the missing tool.
VIVADO ?= vivado

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
# boards are not shipped with Vivado, so VIVADO_BOARD_REPO points at a vendored
# copy — keeping it in the project means a fresh clone builds without modifying
# the Vivado installation.
#   VIVADO_BOARD_REPO := vivado/board_files
#   VIVADO_BOARD_PART := <vendor>:<board>:part0:<version>
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

# ── The simulation verdict ────────────────────────────────────────────────────
# xsim's exit status is not a verdict, so the transcript is read instead.
#
# Measured on 2021.2, because this is the kind of claim that has to be measured:
# a testbench ending in 'assert … severity failure' prints "Failure: <message>"
# and exits 0. A clean run also exits 0. The two are indistinguishable by exit
# status, which means an unchecked 'make sim' reports success on a run where
# every check failed — and a green build that proves nothing is worse than a red
# one. Only a TOOL-level failure exits non-zero (a missing snapshot gives
# "ERROR: Please check the snapshot name …" and exit 1), and the pipe to tee
# below would swallow that too, so it is matched in the transcript as well.
#
# The prefixes are xsim's own rendering of VHDL severities — 'Note:',
# 'Warning:', 'Error:', 'Failure:' — so any testbench that uses assert/report
# gets the default check for free, with no convention imposed on it.
#
#   XSIM_FAIL_PATTERN  extended regex; any match fails the run.
#   XSIM_PASS_PATTERN  extended regex that MUST appear, or the run fails. Empty
#                      by default: a completion marker is a testbench
#                      convention, not something the framework can know. Declare
#                      the project's own in project.mk, e.g.
#                          XSIM_PASS_PATTERN := TEST COMPLETE
#                      That is what catches a run which died quietly somewhere
#                      before the end of the testbench — no failing assert to
#                      match, just a transcript that stops early.
#   XSIM_CHECK         0 skips the verdict, for a run that is EXPECTED to fail:
#                      a TDD red phase asserts the inverse itself, against the
#                      same transcript. Command line only — a project that
#                      disables it permanently has switched the check off.
#
# Patterns are passed to grep -E inside single quotes; a pattern containing a
# single quote will not survive.
XSIM_LOG          ?= $(BUILD_DIR)/xsim_$(VIVADO_SIM_TOP).log
XSIM_FAIL_PATTERN ?= ^(Error|Failure|Fatal):|^ERROR:
XSIM_PASS_PATTERN ?=
XSIM_CHECK        ?= 1

# An empty transcript is a failure in its own right: it means xsim never ran, or
# died before printing anything, and neither pattern can speak to a file with
# nothing in it.
define _xsim_verdict
	@log='$(abspath $(XSIM_LOG))'; \
	if [ ! -s "$$log" ]; then \
	    echo "[XSIM] FAILED — no transcript at $(XSIM_LOG); the simulation did not run."; \
	    exit 1; \
	fi; \
	if grep -Eq '$(XSIM_FAIL_PATTERN)' "$$log"; then \
	    echo "[XSIM] FAILED — transcript matched XSIM_FAIL_PATTERN:"; \
	    grep -E '$(XSIM_FAIL_PATTERN)' "$$log" | head -20 | sed 's/^/[XSIM]     /'; \
	    echo "[XSIM] Full transcript: $(XSIM_LOG)"; \
	    exit 1; \
	fi; \
	$(if $(strip $(XSIM_PASS_PATTERN)),\
	if ! grep -Eq '$(XSIM_PASS_PATTERN)' "$$log"; then \
	    echo "[XSIM] FAILED — XSIM_PASS_PATTERN never appeared: $(XSIM_PASS_PATTERN)"; \
	    echo "[XSIM] The run ended before the testbench reported completion."; \
	    echo "[XSIM] Full transcript: $(XSIM_LOG)"; \
	    exit 1; \
	fi; ,\
	echo "[XSIM] NOTE: XSIM_PASS_PATTERN is unset — a run that stops early still passes."; \
	echo "[XSIM]       Declare the testbench's completion marker in project.mk."; ) \
	echo "[XSIM] PASSED — transcript checked ($(XSIM_LOG))."
endef

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
        sim sim-gui sim-elab vitis-platform vitis-apps vitis-run program \
        _help_vivado

# Listed by 'make help' — see the TOOLCHAIN_HELP_TARGET hook in common.mk.
TOOLCHAIN_HELP_TARGET := _help_vivado

_help_vivado:
	@echo ""
	@echo "  Vivado targets:"
	@echo "    synth          Synthesis only"
	@echo "    impl           Implementation (place & route)"
	@echo "    bitstream      Bitstream — this is what 'all' builds"
	@echo "    xsa            Full flow, then export the .xsa hardware platform"
	@echo "    params         Regenerate the build's TCL parameters"
	@echo ""
	@echo "    sim            Run the xsim testbench in batch"
	@echo "    sim-elab       Elaborate the testbench without running it"
	@echo "    sim-gui        Run the testbench in the xsim GUI"
	@echo ""
	@echo "    project        Build a browsable .xpr from the same sources"
	@echo "    project-gui    Build that project and open it in the IDE"
	@echo "    gui            Open the newest checkpoint in the IDE"
	@echo "    bd-draft       Create the editable block-design project"
	@echo "    bd-gui         Open the block design in the GUI"
	@echo "    bd-export      Export the block design back to TCL"
	@echo ""
	@echo "    vitis-platform Build the Vitis platform from the .xsa"
	@echo "    vitis-apps     Build the Vitis applications"
	@echo "    vitis-run      Download and run VITIS_RUN_APP on the board"
	@echo "    boot-image     Build the boot images named by BOOT_IMAGES"
	@echo ""
	@echo "    program        Load the bitstream into the FPGA over JTAG"
	@echo "    flash-boot     Write the boot images into the board's flash"

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

# Piped through tee so the run stays live on the console and still leaves the
# transcript the verdict is read from. The pipe discards xsim's exit status,
# which is the right trade only because nothing here trusted it in the first
# place — see the verdict block above.
sim: sim-elab
	@echo "[XSIM] Running simulation (batch)..."
	cd $(XSIM_DIR) && $(XSIM) $(XSIM_SNAPSHOT) -runall 2>&1 | tee $(abspath $(XSIM_LOG))
ifeq ($(XSIM_CHECK),0)
	@echo "[XSIM] Verdict SKIPPED (XSIM_CHECK=0). Transcript: $(XSIM_LOG)"
else
	$(_xsim_verdict)
endif

# No verdict here: the GUI run is interactive and the operator is the check.
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

# BSP libraries added to VITIS_DOMAIN before the platform is generated, e.g.
# 'lwip211' for anything using the network stack. A library is part of the
# platform, not of an app, so changing this list means regenerating the
# platform -- see the guard in vitis-platform.
VITIS_LIBS     ?=

# BSP parameters applied to VITIS_DOMAIN before the platform is generated, as
# name=value pairs, e.g. phy_link_speed=CONFIG_LINKSPEED1000. Applied after
# VITIS_LIBS, since a library's parameters only exist once the library does.
# Like VITIS_LIBS, these are platform state -- changing them means regenerating.
VITIS_BSP_CONFIG ?=

# Source DIRECTORIES overlaid onto the platform's generated first-stage
# bootloader, which is then rebuilt with them -- the supported way to hook it,
# since the vendor ships a hooks file that exists to be replaced. Use it for a
# boot arbiter, a hardware bring-up hook, anything that has to run before the
# application does.
#
# WHY THIS EXISTS AT ALL: 'platform generate' writes the bootloader sources
# fresh into the workspace, and the workspace is a build artefact. Editing the
# generated hooks file in place works exactly until the next regeneration
# silently reverts it -- and the failure mode is a board that boots the wrong
# image, not a build error. So the hook lives in version control and the build
# overlays it.
#
#   VITIS_BOOT_SRC := sw/boot_hooks sw/lib/flash sw/lib/bootstate
#
# Directories, listed the same way VITIS_APP_<app>_SRC is, with the files
# discovered per directory rather than enumerated by hand. Headers come along
# with sources: the bootloader compiles everything in its own directory, so a
# copied .h is how an overlay carries its own interface.
#
# A directory containing an application entry point does not belong here -- the
# bootloader has one already. Keep reusable modules in their own directories and
# point at those.
VITIS_BOOT_SRC ?=

# Extensions an overlay copies: the C-family set scan_project.sh already
# discovers, plus headers. Not VHDL -- an overlay targets a software project.
VITIS_OVERLAY_EXTS ?= *.c *.cpp *.cxx *.cc *.s *.S *.asm *.h *.hpp *.hh

# $(call vitis_overlay_files,<dir list>) -> every overlay-eligible file in them.
vitis_overlay_files = \
    $(foreach d,$(1),$(wildcard $(addprefix $(d)/,$(VITIS_OVERLAY_EXTS))))

# Per-app Vitis template, e.g. VITIS_APP_echo_TEMPLATE := lwIP Echo Server.
# Names are version-specific -- list them with 'repo -apps' in xsct. Likewise
# 'repo -libs' for the VITIS_LIBS names above.
VITIS_TEMPLATE ?= Empty Application(C)

# Preprocessor symbols passed to the compiler, as bare names or NAME=VALUE:
#
#   VITIS_DEFINES              := BOARD_REV=2        # every app
#   VITIS_APP_updater_DEFINES  := FAULT_HANG=1       # that app only
#
# Both lists apply, global first. Each becomes -D<symbol> through
# 'app config define-compiler-symbols'.
#
# WHY THIS IS DECLARED AND NOT EDITED: the alternative is setting symbols in the
# Vitis GUI or hand-editing the workspace .cproject, and the workspace is a build
# artefact -- 'app create' and 'importsources' rewrite it. A symbol set there
# survives exactly until the next clean build, and its failure mode is a binary
# that behaves differently from the sources describing it. Same argument as
# VITIS_BOOT_SRC above.
#
# The declared lists are AUTHORITATIVE: whatever symbols the workspace already
# carries are removed before these are applied, so deleting a line here really
# does delete the symbol on the next build instead of leaving it set. That
# matters more than it looks -- a fault-injection or debug symbol left behind
# produces a perfectly working build of the wrong firmware, silently.
VITIS_DEFINES ?=

# $(call vitis_app_defines,<app>) -> the symbols that app compiles with.
vitis_app_defines = $(strip $(VITIS_DEFINES) $(VITIS_APP_$(1)_DEFINES))

# The xsct fragment that makes the declared list authoritative for ONE app.
# Clears whatever the workspace has, then applies ours. The read is wrapped in
# catch because a freshly created app has no value to report, and the separator
# Vitis uses for this parameter is not contracted in its documentation, so the
# split tolerates each one it has been seen to produce.
vitis_app_defines_tcl = \
	echo 'if { [catch { set _d [app config -name $(1) define-compiler-symbols] } _e] } { set _d {} }'; \
	echo 'foreach _s [split $$_d " ;,"] {'; \
	echo '    if { $$_s ne {} } { catch { app config -name $(1) -remove define-compiler-symbols $$_s } }'; \
	echo '}'; \
	$(foreach s,$(call vitis_app_defines,$(1)),\
	    echo 'app config -name $(1) -add define-compiler-symbols $(s)'; \
	    echo 'puts {[VITIS] $(1): -D$(s)}';)

VITIS_PLATFORM_TCL := $(BUILD_DIR)/vitis_platform.tcl
VITIS_BOOT_TCL     := $(BUILD_DIR)/vitis_boot.tcl

# The boot component the platform generates, DISCOVERED rather than named --
# because what it is called depends on the device. Vitis writes zynq_fsbl on
# Zynq-7000, zynqmp_fsbl on ZynqMP, and a Versal platform generates a PLM
# instead; the ELF inside is likewise family-specific. Naming any of them here
# would bake a device family into a framework that is meant to outlive one.
#
# The glob is a variable so a device this list has not met yet can be handled
# from project.mk instead of by patching the framework.
VITIS_BOOT_DIR_GLOB ?= *fsbl* *plm*

# Deferred assignment (=, not :=) on purpose: neither exists until
# 'platform generate' has run.
#
# THE TRAP, learned by walking into it: deferred is still not late enough to use
# these INSIDE the recipe that generates the platform. GNU make expands a whole
# recipe before running its first line, so $(wildcard) there sees the directory
# tree as it was BEFORE 'platform generate' -- and reports nothing. The overlay
# step below therefore discovers the directory in the shell, at the moment it
# needs it. These two are for OTHER targets, which run in a later recipe (a
# boot-image rule, say) by which time the platform exists.
VITIS_BOOT_DIR      = $(firstword $(wildcard \
                          $(addprefix $(VITIS_WS)/$(VITIS_PLATFORM)/,$(VITIS_BOOT_DIR_GLOB))))
VITIS_BOOT_ELF      = $(firstword $(wildcard $(VITIS_BOOT_DIR)/*.elf))
VITIS_APPS_TCL     := $(BUILD_DIR)/vitis_apps.tcl
VITIS_RUN_TCL      := $(BUILD_DIR)/vitis_run.tcl
VITIS_PS_INIT      := $(BUILD_DIR)/ps7_init.tcl

# What each stage leaves behind, so the next stage can check for it up front
# instead of discovering the gap halfway through an xsct session. 'platform.spr'
# is the descriptor Vitis itself uses to recognise a platform project.
VITIS_PLATFORM_SPR := $(VITIS_WS)/$(VITIS_PLATFORM)/platform.spr
VITIS_RUN_ELF      := $(VITIS_WS)/$(VITIS_RUN_APP)/Debug/$(VITIS_RUN_APP).elf

# Deliberately NOT idempotent. Reusing an existing platform would be wrong in
# the case this target is actually run for -- a changed XSA, or a changed
# VITIS_LIBS -- so an existing platform is an error that names its own fix
# rather than a silent reuse of a stale one.
vitis-platform: | $(BUILD_DIR)
	@test -f "$(VIVADO_XSA)" || { \
	    echo "[VITIS] ERROR: no hardware platform at $(VIVADO_XSA)"; \
	    echo "[VITIS] Run 'make xsa' first."; \
	    exit 1; \
	}
	@test ! -f "$(VITIS_PLATFORM_SPR)" || { \
	    echo "[VITIS] ERROR: platform '$(VITIS_PLATFORM)' already exists in $(VITIS_WS)"; \
	    echo "[VITIS] Remove $(VITIS_WS) to regenerate it -- needed after an XSA"; \
	    echo "[VITIS] or VITIS_LIBS change. Apps have to be rebuilt afterwards."; \
	    exit 1; \
	}
	@echo "[VITIS] Generating platform script → $(VITIS_PLATFORM_TCL)"
	@( \
	echo "setws $(abspath $(VITIS_WS))"; \
	echo "platform create -name $(VITIS_PLATFORM) -hw $(abspath $(VIVADO_XSA)) -proc $(VITIS_PROC) -os $(VITIS_OS)"; \
	$(if $(strip $(VITIS_LIBS))$(strip $(VITIS_BSP_CONFIG)), \
	    echo 'domain active {$(VITIS_DOMAIN)}';) \
	$(foreach l,$(VITIS_LIBS),echo "bsp setlib -name $(l)";) \
	$(foreach c,$(VITIS_BSP_CONFIG),echo "bsp config $(subst =, ,$(c))";) \
	echo "platform generate"; \
	) > $(VITIS_PLATFORM_TCL)
	$(if $(strip $(VITIS_LIBS)),@echo "[VITIS] BSP libraries: $(VITIS_LIBS)")
	$(if $(strip $(VITIS_BSP_CONFIG)),@echo "[VITIS] BSP config: $(VITIS_BSP_CONFIG)")
	@echo "[VITIS] Building platform $(VITIS_PLATFORM)..."
	$(XSCT) $(VITIS_PLATFORM_TCL)
ifneq ($(strip $(VITIS_BOOT_SRC)),)
	@$(foreach d,$(VITIS_BOOT_SRC), \
	    test -d "$(d)" || { echo "[VITIS] ERROR: no such directory: $(d)"; exit 1; };)
	@test -n "$(strip $(call vitis_overlay_files,$(VITIS_BOOT_SRC)))" || { \
	    echo "[VITIS] ERROR: VITIS_BOOT_SRC matched no source files."; \
	    echo "[VITIS]        Searched for: $(VITIS_OVERLAY_EXTS)"; \
	    exit 1; \
	}
	@set -e; \
	bootdir=$$(ls -d $(addprefix $(VITIS_WS)/$(VITIS_PLATFORM)/,$(VITIS_BOOT_DIR_GLOB)) \
	           2>/dev/null | head -1); \
	test -n "$$bootdir" || { \
	    echo "[VITIS] ERROR: VITIS_BOOT_SRC is set, but this platform generated"; \
	    echo "[VITIS]        no bootloader project under $(VITIS_WS)/$(VITIS_PLATFORM)."; \
	    echo "[VITIS]        Looked for: $(VITIS_BOOT_DIR_GLOB)"; \
	    echo "[VITIS] Only a platform whose domain builds one has anything to overlay."; \
	    exit 1; \
	}; \
	echo "[VITIS] Overlaying bootloader sources into $$(basename $$bootdir):"; \
	for f in $(call vitis_overlay_files,$(VITIS_BOOT_SRC)); do \
	    echo "         $$f"; \
	    cp -f "$$f" "$$bootdir/"; \
	done
	@echo "[VITIS] Rebuilding the bootloader with the overlay..."
	@( \
	echo "setws $(abspath $(VITIS_WS))"; \
	echo "platform active $(VITIS_PLATFORM)"; \
	echo "platform generate"; \
	) > $(VITIS_BOOT_TCL)
	$(XSCT) $(VITIS_BOOT_TCL)
	@set -e; \
	bootdir=$$(ls -d $(addprefix $(VITIS_WS)/$(VITIS_PLATFORM)/,$(VITIS_BOOT_DIR_GLOB)) \
	           2>/dev/null | head -1); \
	elf=$$(ls "$$bootdir"/*.elf 2>/dev/null | head -1); \
	test -n "$$elf" || { \
	    echo "[VITIS] ERROR: the bootloader produced no ELF after the overlay."; \
	    echo "[VITIS]        Looked in $$bootdir"; exit 1; }; \
	echo "[VITIS] Hooked bootloader: $$elf"
endif

# The xsct fragment that creates (when absent), overlays and builds ONE app.
# Shared by vitis-apps, which does every app in VITIS_APPS, and by the ELF rule
# further down, which does a single one. $(1) is the app name.
#
# 'app create' is guarded by a file-existence test rather than a bare catch, so
# that re-runs are still idempotent but a genuine failure keeps its own error
# message. Wrapping it in 'catch' hides the real cause — a missing platform
# reports only "The project given does not exist in workspace" from the later
# 'app build', which points at the wrong thing entirely.
vitis_app_tcl = \
	echo 'if { [file exists {$(abspath $(VITIS_WS))/$(1)/.project}] } {'; \
	echo '    puts {[VITIS] app $(1) already exists - reusing}'; \
	echo '} else {'; \
	echo '    app create -name $(1) -platform $(VITIS_PLATFORM) -domain $(VITIS_DOMAIN) -template {$(or $(VITIS_APP_$(1)_TEMPLATE),$(VITIS_TEMPLATE))}'; \
	echo '}'; \
	$(foreach d,$(VITIS_APP_$(1)_SRC),\
	    echo "importsources -name $(1) -path $(abspath $(d))";) \
	$(call vitis_app_defines_tcl,$(1)) \
	echo "app build -name $(1)";

# Files whose modification makes an app's ELF stale: its version-controlled
# overlay directories, if it has any -- VITIS_APP_<app>_SRC is a list, so an app
# can pull in shared module directories alongside its own. The workspace copy
# under $(VITIS_WS) is a
# build artefact -- importsources rewrites it on every build, so treating it as
# a prerequisite would rebuild forever. An app built purely from a vendor
# template therefore has no prerequisites and is built only when its ELF is
# missing; to iterate on a template's own sources, copy the file you want to
# change into the overlay directory, which is where edits belong anyway.
vitis_app_srcs = $(foreach d,$(VITIS_APP_$(1)_SRC),$(shell find $(d) -type f 2>/dev/null))

vitis-apps: | $(BUILD_DIR)
	@test -n "$(strip $(VITIS_APPS))" || { echo "[VITIS] ERROR: VITIS_APPS is empty"; exit 1; }
	@test -f "$(VITIS_PLATFORM_SPR)" || { \
	    echo "[VITIS] ERROR: no platform '$(VITIS_PLATFORM)' in $(VITIS_WS)"; \
	    echo "[VITIS] Run 'make vitis-platform' first."; \
	    exit 1; \
	}
	@echo "[VITIS] Generating app script → $(VITIS_APPS_TCL)"
	@( \
	echo "setws $(abspath $(VITIS_WS))"; \
	$(foreach a,$(VITIS_APPS),$(call vitis_app_tcl,$(a))) \
	) > $(VITIS_APPS_TCL)
	@echo "[VITIS] Building app(s): $(VITIS_APPS)"
	$(XSCT) $(VITIS_APPS_TCL)

# Build one app's ELF when its sources are newer, or when it is missing. This
# is what lets an edit-and-run cycle be a single 'make vitis-run': the ELF is a
# real file with real prerequisites, so make decides whether xsct needs to run
# at all. vitis-apps stays available for rebuilding everything on purpose.
$(VITIS_RUN_ELF): $(call vitis_app_srcs,$(VITIS_RUN_APP)) | $(BUILD_DIR)
	@test -f "$(VITIS_PLATFORM_SPR)" || { \
	    echo "[VITIS] ERROR: no platform '$(VITIS_PLATFORM)' in $(VITIS_WS)"; \
	    echo "[VITIS] Run 'make vitis-platform' first."; \
	    exit 1; \
	}
	@echo "[VITIS] $(VITIS_RUN_APP) is out of date — rebuilding"
	@( \
	echo "setws $(abspath $(VITIS_WS))"; \
	$(call vitis_app_tcl,$(VITIS_RUN_APP)) \
	) > $(VITIS_APPS_TCL)
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
#     "AHB AP transaction error", recoverable only by replugging the cable.
#     BOTH cores, not just #0. Until 2026-08-13 this script stopped core#1 at the
#     top and never resumed it: the closing 'con' lands on core#0, because the
#     target was switched two lines earlier. Every run therefore left an A9
#     halted, and the DAP wedged on some later connect — intermittently, which
#     is what made it look like flaky hardware rather than a missing line. Three
#     wedges in one session, each costing a physical replug of J14, before the
#     asymmetry between the stop and the resume was spotted.
#   tolerate an already-stopped core #1 — xsct raises "Already stopped" on a
#     redundant 'stop', so any run that aborted while halted would otherwise
#     poison every following run at line 4, before it can reset anything
# Depends on the ELF rather than merely checking for it, so a source edit is
# picked up by 'make vitis-run' alone. The dependency is suppressed when
# VITIS_RUN_APP is empty, so that case still reaches the explicit error below
# instead of make trying to build a nonsense path.
vitis-run: $(if $(strip $(VITIS_RUN_APP)),$(VITIS_RUN_ELF)) | $(BUILD_DIR)
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
	echo 'if { [catch { stop } msg] } { puts "core#1 stop skipped: $$msg" }'; \
	echo 'targets -set -filter {name =~ "*Cortex-A9*#0"}'; \
	echo "rst -processor"; \
	echo "after 1000"; \
	echo "source $(abspath $(VITIS_PS_INIT))"; \
	echo "ps7_init"; \
	echo "ps7_post_config"; \
	echo "fpga -file $(abspath $(VIVADO_BIT))"; \
	echo "dow $(abspath $(VITIS_RUN_ELF))"; \
	echo "con"; \
	echo 'targets -set -filter {name =~ "*Cortex-A9*#1"}'; \
	echo 'if { [catch { con } msg] } { puts "core#1 resume skipped: $$msg" }'; \
	echo 'targets -set -filter {name =~ "*Cortex-A9*#0"}'; \
	) > $(VITIS_RUN_TCL)
	@echo "[VITIS] Running $(VITIS_RUN_APP) on hardware..."
	$(XSCT) $(VITIS_RUN_TCL)

# ── Boot images: bootgen + program_flash (Zynq-7000) ──────────────────────────
# The non-volatile path. Everything above this point puts things in volatile
# memory — a bitstream in PL SRAM, an ELF in DDR — and vanishes on a power
# cycle. These two targets are what survive it.
#
#   boot-image   build a BOOT.BIN from a .bif with bootgen
#   flash-boot   write each BOOT.BIN into QSPI at its offset, with verification
#
# WHY bootgen AND NOT write_cfgmem
#
# write_cfgmem is the Vivado primitive for a plain FPGA that boots a raw
# bitstream out of SPI flash. A Zynq-7000 does not do that: the BootROM loads a
# BOOT.BIN boot image (FSBL + optional bitstream + application), which is what
# bootgen builds from a .bif. write_cfgmem is still worth adding here one day as
# the non-Zynq path; it is not this.
#
# Declare images in project.mk:
#
#   BOOT_IMAGES            := golden update
#   BOOT_golden_BIF        := boot/golden.bif
#   BOOT_golden_OFFSET     := 0x000000
#   BOOT_update_BIF        := boot/update.bif
#   BOOT_update_OFFSET     := 0x700000
#
# Paths inside a .bif are resolved relative to the directory make runs from,
# i.e. the project root — so write them repo-root-relative and they behave the
# same for everyone.
#
# THE BOARD MUST BE IN JTAG BOOT MODE WHILE FLASHING. program_flash reaches the
# QSPI through a helper FSBL it downloads over JTAG; if the board is set to boot
# from the flash being written, it is booting out of the memory under the pen.
# Which of the built images flash-boot actually WRITES. Defaults to all of them,
# which is right for a project whose every image reaches the board through the
# programmer.
#
# It is separate from BOOT_IMAGES because building an image and flashing it are
# different decisions. An A/B update design has at least one image that is built
# here and delivered some other way entirely -- over the network, by an updater
# that verifies it before and after programming. Flashing such an image directly
# is not a shortcut, it bypasses the mechanism the image exists to exercise, so
# the framework lets a project build it without ever offering it to the pen.
#
#   BOOT_IMAGES       := golden update    both built
#   BOOT_FLASH_IMAGES := golden           only this one written over JTAG
BOOT_FLASH_IMAGES ?= $(BOOT_IMAGES)

BOOTGEN          ?= $(dir $(XSCT))bootgen
PROGRAM_FLASH    ?= $(dir $(XSCT))program_flash
BOOT_IMAGES      ?=
BOOT_DIR         ?= $(BUILD_DIR)/boot
# bootgen's -arch. DELIBERATELY HAS NO DEFAULT: it is a device-family fact, and
# a wrong one fails silently. bootgen does not cross-check -arch against the
# .bif -- it reports "Bootimage generated successfully" and exits 0 while
# emitting an image with the other family's boot header, which the BootROM then
# refuses. A default would make that the outcome of forgetting one line.
# Declare it in project.mk: zynq | zynqmp | versal.
BOOT_ARCH        ?=
BOOT_FLASH_TYPE  ?= qspi_single
# program_flash needs an FSBL to act as its flash writer. The platform's
# generated one is the right default; override for a hooked FSBL.
#
# DISCOVERED, not named: VITIS_BOOT_ELF resolves whatever the platform actually
# generated -- zynq_fsbl/fsbl.elf, zynqmp_fsbl/fsbl.elf or a Versal PLM -- so
# this default does not assume a device family. Deferred expansion, because the
# platform does not exist until 'make vitis-platform' has run.
BOOT_FSBL        ?= $(VITIS_BOOT_ELF)
BOOT_HW_URL      ?= TCP:127.0.0.1:3121

# program_flash must LAUNCH its own hw_server, not attach to a running one.
#
# It attaches when something is already listening on BOOT_HW_URL, and an
# hw_server started by anything else leaves the cable enumerated but the chain
# unopened -- `jtag targets` shows the cable "(closed)" with no arm_dap or
# device, and program_flash fails with "ERROR: Given target do not exist". The
# working case is program_flash printing "Failed to connect to hw_server ...
# Attempting to launch hw_server" and starting its own.
#
# Any prior JTAG contact in the same session causes this: an `xsct` invocation,
# a `connect`, a chain probe, a Hardware Manager left open. Set to 0 when
# BOOT_HW_URL points at a hw_server you deliberately run (a remote or shared
# cable), since then attaching is the intent.
BOOT_HW_SERVER_RESET ?= 1

boot_image_bin = $(BOOT_DIR)/$(1).bin

.PHONY: boot-image flash-boot

boot-image: | $(BUILD_DIR)
	@test -n "$(strip $(BOOT_IMAGES))" || { \
	    echo "[BOOT] ERROR: BOOT_IMAGES is empty."; \
	    echo "[BOOT] Declare images in project.mk — see mk/make/vivado.mk."; \
	    exit 1; \
	}
	@test -n "$(strip $(BOOT_ARCH))" || { \
	    echo "[BOOT] ERROR: BOOT_ARCH is not set."; \
	    echo "[BOOT] bootgen needs the device family, and guessing it is worse"; \
	    echo "[BOOT] than refusing: bootgen accepts a wrong -arch, exits 0, and"; \
	    echo "[BOOT] writes an image the BootROM will not load."; \
	    echo "[BOOT] Set it in project.mk:  BOOT_ARCH := zynq | zynqmp | versal"; \
	    exit 1; \
	}
	@command -v $(BOOTGEN) >/dev/null 2>&1 || test -x "$(BOOTGEN)" || { \
	    echo "[BOOT] ERROR: bootgen not found at '$(BOOTGEN)'"; \
	    echo "[BOOT] It ships with Vitis; set BOOTGEN or XSCT to point at it."; \
	    exit 1; \
	}
	@mkdir -p $(BOOT_DIR)
	@$(foreach i,$(BOOT_IMAGES), \
	    test -n "$(BOOT_$(i)_BIF)" || { echo "[BOOT] ERROR: BOOT_$(i)_BIF is not set"; exit 1; }; \
	    test -f "$(BOOT_$(i)_BIF)" || { echo "[BOOT] ERROR: no .bif at $(BOOT_$(i)_BIF)"; exit 1; }; \
	    echo "[BOOT] bootgen $(i): $(BOOT_$(i)_BIF) → $(call boot_image_bin,$(i))"; \
	    $(BOOTGEN) -arch $(BOOT_ARCH) -image $(BOOT_$(i)_BIF) \
	               -o $(abspath $(call boot_image_bin,$(i))) -w on || exit 1; \
	)
	@echo "[BOOT] Images:"
	@ls -l $(BOOT_DIR)

# Deliberately separate from boot-image: building an image is cheap and
# repeatable, writing flash is neither.
flash-boot:
	@test -n "$(strip $(BOOT_FLASH_IMAGES))" || { \
	    echo "[BOOT] ERROR: BOOT_FLASH_IMAGES is empty (BOOT_IMAGES is '$(BOOT_IMAGES)')"; \
	    exit 1; }
	@# Clear a stale local hw_server so program_flash starts its own -- see
	@# BOOT_HW_SERVER_RESET above for why attaching to one breaks the target.
	@if [ "$(BOOT_HW_SERVER_RESET)" = "1" ]; then \
	    case "$(BOOT_HW_URL)" in \
	    *127.0.0.1*|*localhost*) \
	        pids=`pgrep -x hw_server 2>/dev/null`; \
	        if [ -n "$$pids" ]; then \
	            echo "[BOOT] a hw_server is already running (PID $$pids)."; \
	            echo "[BOOT] program_flash would attach to it and fail with"; \
	            echo "[BOOT] 'Given target do not exist'. Stopping it first."; \
	            for p in $$pids; do kill $$p 2>/dev/null || true; done; \
	            sleep 1; \
	            still=`pgrep -x hw_server 2>/dev/null`; \
	            if [ -n "$$still" ]; then \
	                for p in $$still; do kill -9 $$p 2>/dev/null || true; done; \
	                sleep 1; \
	            fi; \
	            if [ -n "`pgrep -x hw_server 2>/dev/null`" ]; then \
	                echo "[BOOT] ERROR: hw_server still running; stop it and retry."; \
	                exit 1; \
	            fi; \
	        fi ;; \
	    esac; \
	fi
	@test -f "$(BOOT_FSBL)" || { \
	    echo "[BOOT] ERROR: no FSBL at $(BOOT_FSBL)"; \
	    echo "[BOOT] program_flash downloads one over JTAG to drive the QSPI."; \
	    echo "[BOOT] 'make vitis-platform' generates it; override BOOT_FSBL to change it."; \
	    exit 1; \
	}
	@$(foreach i,$(BOOT_FLASH_IMAGES), \
	    test -f "$(call boot_image_bin,$(i))" || { \
	        echo "[BOOT] ERROR: no image at $(call boot_image_bin,$(i)) — run 'make boot-image'"; exit 1; }; \
	    test -n "$(BOOT_$(i)_OFFSET)" || { echo "[BOOT] ERROR: BOOT_$(i)_OFFSET is not set"; exit 1; }; \
	    echo "[BOOT] program_flash $(i) → $(BOOT_$(i)_OFFSET)"; \
	    $(PROGRAM_FLASH) -f $(abspath $(call boot_image_bin,$(i))) \
	                     -offset $(BOOT_$(i)_OFFSET) \
	                     -flash_type $(BOOT_FLASH_TYPE) \
	                     -fsbl $(abspath $(BOOT_FSBL)) \
	                     -verify \
	                     -cable type xilinx_tcf url $(BOOT_HW_URL) || exit 1; \
	)
	@echo "[BOOT] All images written and verified."

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
