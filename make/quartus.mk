# ==============================================================================
# quartus.mk — Intel/Altera Quartus Prime toolchain rules
# Handles: VHDL / Verilog / SV → synthesis → fit → assembly → STA → .sof
#          Platform Designer systems → generated HDL → the Quartus project
#          Nios II BSP + applications → .elf
#
# ── Compilation order strategy ────────────────────────────────────────────────
# Quartus's analysis & synthesis (quartus_map) reads all sources specified in
# the QSF.  For VHDL, the file order in QSF matters for older VHDL standards;
# VHDL-2008 in Quartus is more tolerant but still benefits from correct order.
# VHDL_SRCS order is controlled by per-directory .compile_order files (Layer 2)
# or VHDL_SRCS_DIR in project.mk (Layer 1 — list directories in order).
# ==============================================================================

# ── Tool names ───────────────────────────────────────────────────────────────
# Defaulted rather than required: a project.mk that declares only its device
# should build. Without these an unset variable expands to nothing and the
# recipe runs its own first flag as the command, which fails as "not found"
# and points at the flag rather than at the missing tool name.
QUARTUS_SH  ?= quartus_sh
QUARTUS_MAP ?= quartus_map
QUARTUS_FIT ?= quartus_fit
QUARTUS_ASM ?= quartus_asm
QUARTUS_STA ?= quartus_sta
QUARTUS_PGM ?= quartus_pgm

# ── Constraints ──────────────────────────────────────────────────────────────
# The QSF is regenerated on every build, so a pin placement written into it by
# hand does not survive. Projects declare constraints as files instead:
#
#   QUARTUS_QSF_EXTRA  files appended verbatim into the generated QSF —
#                      set_location_assignment, IO_STANDARD, device settings
#   QUARTUS_SDC        .sdc timing constraints, added as SDC_FILE assignments
#
# Both are project facts. Nothing about a pin, a board or a clock belongs in
# this file.
QUARTUS_QSF_EXTRA ?=
QUARTUS_SDC       ?=

# ── VHDL standard ────────────────────────────────────────────────────────────
# VHDL-2008 for every source by default; list the exceptions in QUARTUS_VHDL93.
# Same shape as the Vivado toolchain's VIVADO_VHDL93, so a project that spans
# both vendors declares the exception once per toolchain and not per file.
QUARTUS_VHDL_VERSION ?= VHDL_2008
QUARTUS_VHDL93       ?=

# ── On-chip memory initialisation ────────────────────────────────────────────
# NIOS_MEM_INIT names the application whose program is baked into the FPGA
# image. A Nios II booting from on-chip memory has nothing to run otherwise:
# the .sof carries an empty RAM, and the program normally arrives afterwards
# over a JTAG debug download. Where that download is not available — no cable
# driver, or a board expected to run standalone — the program has to be in the
# image, which means the software must be built BEFORE the FPGA image.
#
# Declaring it inverts the usual order: synthesis waits for the .elf.
NIOS_MEM_INIT ?=
NIOS_DIR      := $(BUILD_DIR)/nios
NIOS_MEM_INIT_QIP = $(if $(NIOS_MEM_INIT),$(NIOS_DIR)/$(NIOS_MEM_INIT)/app/mem_init/meminit.qip)

# ── Platform Designer and Nios II tool location ──────────────────────────────
# Sourcing the Quartus environment puts quartus/linux64 and the simulator on
# PATH and nothing else. qsys-generate lives under quartus/sopc_builder/bin and
# the Nios II SDK under nios2eds/, neither of which is added — so a bare
# 'qsys-generate' is "command not found" in an otherwise working shell.
#
# nios2_command_shell.sh is the vendor's answer: given a command it runs it with
# all three directories on PATH. Given NO arguments it drops into an interactive
# bash, which is why it is invoked as a wrapper here and must never be sourced
# from a recipe — sourcing it never returns.
#
# QUARTUS_ROOTDIR is exported by the Quartus environment (adm/qenv.sh); the
# install root is its parent. A project may override NIOS2_SHELL outright when
# the tools live somewhere unusual.
ACDS_ROOT   ?= $(abspath $(QUARTUS_ROOTDIR)/..)
NIOS2_SHELL ?= $(ACDS_ROOT)/nios2eds/nios2_command_shell.sh

# Guard used by every target below that needs the wrapper. A missing wrapper is
# an environment problem and says so, rather than surfacing as a cryptic
# "command not found" from inside a generated makefile.
define _require_nios2_shell
	@test -x "$(NIOS2_SHELL)" || { \
	    echo "[QUARTUS] error: Nios II command shell not found at $(NIOS2_SHELL)"; \
	    echo "[QUARTUS]        Set QUARTUS_ROOTDIR (or NIOS2_SHELL) so it resolves."; \
	    exit 1; }
endef

# ── Platform Designer ────────────────────────────────────────────────────────
# QSYS_SYSTEMS lists .qsys files; QSYS_LANG picks the synthesis language.
#
# Each system is COPIED into the build tree before generation. That is not
# tidiness: qsys-generate honours --output-directory for the HDL but writes the
# .sopcinfo next to the .qsys it was handed, so generating in place drops a
# 170 kB generated file into the source tree on every build. Generating from a
# staged copy keeps every artefact under BUILD_DIR.
QSYS_LANG ?= VERILOG
QSYS_DIR  := $(BUILD_DIR)/qsys

_qsys_name  = $(basename $(notdir $(1)))
_qsys_staged= $(QSYS_DIR)/$(call _qsys_name,$(1))/$(notdir $(1))
_qsys_gen   = $(QSYS_DIR)/$(call _qsys_name,$(1))/generated
_qsys_qip   = $(call _qsys_gen,$(1))/synthesis/$(call _qsys_name,$(1)).qip
_qsys_spc   = $(QSYS_DIR)/$(call _qsys_name,$(1))/$(call _qsys_name,$(1)).sopcinfo

QSYS_QIPS := $(foreach q,$(QSYS_SYSTEMS),$(call _qsys_qip,$(q)))

# One rule per declared system. The .qip is the target because it is what the
# QSF consumes; the .sopcinfo lands beside the staged copy in the same run.
define _qsys_rule
$(call _qsys_qip,$(1)): $(1)
	@echo "[QSYS] Generating $(call _qsys_name,$(1))..."
	$$(call _require_nios2_shell)
	@$(MKDIR) $(dir $(call _qsys_staged,$(1)))
	@cp $(1) $(call _qsys_staged,$(1))
	@"$(NIOS2_SHELL)" qsys-generate $(call _qsys_staged,$(1)) \
	    --synthesis=$(QSYS_LANG) \
	    --output-directory=$(call _qsys_gen,$(1)) \
	    --part=$(QUARTUS_PART)
endef
$(foreach q,$(QSYS_SYSTEMS),$(eval $(call _qsys_rule,$(q))))

qsys: $(QSYS_QIPS)
	@$(if $(QSYS_SYSTEMS),echo "[QSYS] $(words $(QSYS_SYSTEMS)) system(s) generated.",echo "[QSYS] No QSYS_SYSTEMS declared — nothing to do.")

QUARTUS_PROJDIR := $(BUILD_DIR)/quartus_proj
QSF_FILE        := $(QUARTUS_PROJDIR)/$(PROJECT_NAME).qsf
QPF_FILE        := $(QUARTUS_PROJDIR)/$(PROJECT_NAME).qpf
SOF_FILE        := $(QUARTUS_PROJDIR)/$(PROJECT_NAME).sof

# Project-root path as seen from the Quartus project directory. realpath fails
# when that directory does not exist yet — on the very first build — so the
# fallback must be spelled the same way realpath spells it, without a trailing
# slash, or the first QSF written differs from every later one.
_ROOT_REL := $(shell realpath --relative-to=$(QUARTUS_PROJDIR) . 2>/dev/null || echo "../..")

.PHONY: all synth fit asm sta program qsys nios-bsp nios-apps _help_quartus

# Listed by 'make help' — see the TOOLCHAIN_HELP_TARGET hook in common.mk.
TOOLCHAIN_HELP_TARGET := _help_quartus

_help_quartus:
	@echo ""
	@echo "  Quartus targets:"
	@echo "    synth      Analysis & synthesis"
	@echo "    fit        Fitter (place & route)"
	@echo "    asm        Assembler — produces the .sof"
	@echo "    sta        Timing analysis — this is what 'all' builds"
	@echo "    program    Load the .sof into the device over JTAG"
	@echo "    qsys       Generate HDL from every QSYS_SYSTEMS entry"
	@echo "    nios-bsp   Generate the board support package for each Nios II app"
	@echo "    nios-apps  Build every NIOS_APPS entry into an .elf"

all: sta

$(QUARTUS_PROJDIR):
	$(MKDIR) $(QUARTUS_PROJDIR)

# ── Generate Quartus project files ────────────────────────────────────────────
# VHDL_FILE assignments are written in VHDL_SRCS order, which reflects the
# .compile_order files produced by 'make scan'.
#
# Platform Designer output enters as a QIP_FILE, not as enumerated sources: the
# .qip Platform Designer emits already lists every generated file in the right
# order, and it is regenerated whenever the system changes. Enumerating the
# generated tree instead would be a hand-maintained list of files the tool owns.
# Generated HDL is deliberately absent from V_SRCS/VHDL_SRCS — it is a build
# artefact under BUILD_DIR, and 'make scan' does not look there.
$(QPF_FILE): | $(QUARTUS_PROJDIR)
	@echo "[QUARTUS] Generating project file: $(QPF_FILE)"
	@( \
	echo "QUARTUS_VERSION = \"21.1\""; \
	echo "PROJECT_REVISION = \"$(PROJECT_NAME)\""; \
	) > $@

$(QSF_FILE): $(VHDL_SRCS) $(V_SRCS) $(QSYS_QIPS) $(NIOS_MEM_INIT_QIP) $(QUARTUS_QSF_EXTRA) $(QUARTUS_SDC) $(QPF_FILE)
	@echo "[QUARTUS] Generating settings file: $(QSF_FILE)"
	@( \
	echo "set_global_assignment -name FAMILY \"$(patsubst \"%\",%,$(QUARTUS_FAMILY))\""; \
	echo "set_global_assignment -name DEVICE $(QUARTUS_PART)"; \
	echo "set_global_assignment -name TOP_LEVEL_ENTITY $(QUARTUS_TOP)"; \
	echo "set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files"; \
	$(foreach f,$(VHDL_SRCS),\
	    echo "set_global_assignment -name VHDL_FILE $(_ROOT_REL)/$(f) -hdl_version $(if $(filter $(f),$(QUARTUS_VHDL93)),VHDL_1993,$(QUARTUS_VHDL_VERSION))";) \
	$(foreach f,$(V_SRCS),\
	    echo "set_global_assignment -name VERILOG_FILE $(_ROOT_REL)/$(f)";) \
	$(foreach f,$(QSYS_QIPS) $(NIOS_MEM_INIT_QIP),\
	    echo "set_global_assignment -name QIP_FILE $(_ROOT_REL)/$(f)";) \
	$(foreach f,$(QUARTUS_SDC),\
	    echo "set_global_assignment -name SDC_FILE $(_ROOT_REL)/$(f)";) \
	$(foreach f,$(QUARTUS_QSF_EXTRA),cat $(f);) \
	) > $@

# ── Analysis & synthesis ─────────────────────────────────────────────────────
# quartus_map takes the project path and reads the .qsf sitting beside it. It is
# NOT given --source: that flag adds a DESIGN file, so handing it the settings
# file makes Quartus try to elaborate the .qsf and report the real top level as
# undefined. Nor --part: the device belongs in one place, and that is the .qsf.
synth: $(QSYS_QIPS) $(NIOS_MEM_INIT_QIP) $(QSF_FILE)
	@echo "[QUARTUS] Analysis and synthesis..."
	$(QUARTUS_MAP) --read_settings_files=on --write_settings_files=off \
	    $(QUARTUS_PROJDIR)/$(PROJECT_NAME)

# ── Fitter ────────────────────────────────────────────────────────────────────
fit: synth
	@echo "[QUARTUS] Fitting..."
	$(QUARTUS_FIT) --read_settings_files=on --write_settings_files=off \
	    $(QUARTUS_PROJDIR)/$(PROJECT_NAME)

# ── Assembler ─────────────────────────────────────────────────────────────────
asm: fit
	@echo "[QUARTUS] Assembly (generating .sof)..."
	$(QUARTUS_ASM) --read_settings_files=on --write_settings_files=off \
	    $(QUARTUS_PROJDIR)/$(PROJECT_NAME)

# ── Static timing analysis ────────────────────────────────────────────────────
sta: asm
	@echo "[QUARTUS] Static timing analysis..."
	$(QUARTUS_STA) $(QUARTUS_PROJDIR)/$(PROJECT_NAME)
	@echo "[QUARTUS] Build complete: $(SOF_FILE)"

# ── Program device ────────────────────────────────────────────────────────────
program:
	@echo "[QUARTUS] Programming device..."
	$(QUARTUS_PGM) -m jtag -o "p;$(SOF_FILE)"

# ── Nios II software ─────────────────────────────────────────────────────────
# NIOS_APPS names the applications to build. Per application:
#
#   NIOS_<app>_SRC_DIR    where its sources live                     (required)
#   NIOS_<app>_SOPCINFO   the system it runs on                      (derived when
#                         exactly one QSYS_SYSTEMS entry is declared)
#   NIOS_<app>_BSP_TYPE   BSP flavour, defaults to NIOS_BSP_TYPE
#   NIOS_<app>_BSP_SETTINGS  BSP settings as name=value pairs, e.g.
#                         hal.enable_small_c_library=true
#   NIOS_<app>_CFLAGS     extra compiler flags
#
# The BSP and the generated application makefile are build artefacts and live
# under BUILD_DIR. --src-dir points back at the project's sources, so nothing is
# written next to them.
NIOS_BSP_TYPE ?= hal

_nios_bsp_dir = $(NIOS_DIR)/$(1)/bsp
_nios_app_dir = $(NIOS_DIR)/$(1)/app
_nios_elf     = $(call _nios_app_dir,$(1))/$(1).elf
_nios_bsp_lib = $(call _nios_bsp_dir,$(1))/libhal_bsp.a

# A single declared system is unambiguous, so the .sopcinfo is derived from it.
# With several, the project must say which one an application runs on — guessing
# would silently build against the wrong memory map.
_nios_sopcinfo = $(if $(NIOS_$(1)_SOPCINFO),$(NIOS_$(1)_SOPCINFO),\
    $(if $(filter 1,$(words $(QSYS_SYSTEMS))),$(call _qsys_spc,$(firstword $(QSYS_SYSTEMS)))))

NIOS_ELFS := $(foreach a,$(NIOS_APPS),$(call _nios_elf,$(a)))
NIOS_BSPS := $(foreach a,$(NIOS_APPS),$(call _nios_bsp_dir,$(a))/settings.bsp)

define _nios_rule
$(call _nios_bsp_dir,$(1))/settings.bsp: $(call _nios_sopcinfo,$(1))
	@echo "[NIOS] BSP for $(1)..."
	$$(call _require_nios2_shell)
	@test -n "$(call _nios_sopcinfo,$(1))" || { \
	    echo "[NIOS] error: NIOS_$(1)_SOPCINFO is not set and cannot be derived."; \
	    echo "[NIOS]        Set it, or declare exactly one QSYS_SYSTEMS entry."; \
	    exit 1; }
	@$(MKDIR) $(call _nios_bsp_dir,$(1))
	@"$(NIOS2_SHELL)" nios2-bsp \
	    $(if $(NIOS_$(1)_BSP_TYPE),$(NIOS_$(1)_BSP_TYPE),$(NIOS_BSP_TYPE)) \
	    $(call _nios_bsp_dir,$(1)) $(call _nios_sopcinfo,$(1)) \
	    $(foreach kv,$(NIOS_$(1)_BSP_SETTINGS),--set $(firstword $(subst =, ,$(kv))) $(word 2,$(subst =, ,$(kv))))

$(call _nios_elf,$(1)): $(call _nios_bsp_dir,$(1))/settings.bsp $(wildcard $(NIOS_$(1)_SRC_DIR)/*)
	@echo "[NIOS] Application $(1)..."
	$$(call _require_nios2_shell)
	@test -n "$(NIOS_$(1)_SRC_DIR)" || { \
	    echo "[NIOS] error: NIOS_$(1)_SRC_DIR is not set."; exit 1; }
	@$(MKDIR) $(call _nios_app_dir,$(1))
	@"$(NIOS2_SHELL)" nios2-app-generate-makefile \
	    --bsp-dir $(call _nios_bsp_dir,$(1)) \
	    --app-dir $(call _nios_app_dir,$(1)) \
	    --src-dir $(NIOS_$(1)_SRC_DIR) \
	    --elf-name $(1).elf \
	    $(if $(NIOS_$(1)_CFLAGS),--set APP_CFLAGS_USER_FLAGS "$(NIOS_$(1)_CFLAGS)")
	@"$(NIOS2_SHELL)" $(MAKE) -C $(call _nios_app_dir,$(1))
endef
$(foreach a,$(NIOS_APPS),$(eval $(call _nios_rule,$(a))))

# mem_init_generate is a target of the BSP-generated application makefile, so it
# runs there rather than being reimplemented here.
$(NIOS_MEM_INIT_QIP): $(if $(NIOS_MEM_INIT),$(call _nios_elf,$(NIOS_MEM_INIT)))
	@echo "[NIOS] Memory initialisation from $(NIOS_MEM_INIT)..."
	$(call _require_nios2_shell)
	@"$(NIOS2_SHELL)" $(MAKE) -C $(call _nios_app_dir,$(NIOS_MEM_INIT)) mem_init_generate

nios-bsp: $(NIOS_BSPS)
	@$(if $(NIOS_APPS),echo "[NIOS] $(words $(NIOS_APPS)) BSP(s) ready.",echo "[NIOS] No NIOS_APPS declared — nothing to do.")

nios-apps: $(NIOS_ELFS)
	@$(if $(NIOS_APPS),echo "[NIOS] $(words $(NIOS_APPS)) application(s) built.",echo "[NIOS] No NIOS_APPS declared — nothing to do.")

$(BUILD_DIR)/$(PROJECT_NAME): sta

$(BUILD_DIR):
	$(MKDIR) $@
