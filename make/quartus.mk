# ==============================================================================
# quartus.mk — Intel/Altera Quartus Prime toolchain rules
# Handles: VHDL / Verilog / SV → synthesis → fit → assembly → STA → .sof
#          Platform Designer systems → generated HDL → the Quartus project
#          Nios II BSP + applications → .elf
#          Nios V BSP + applications → .elf
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
QUARTUS_CPF ?= quartus_cpf

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

# Nios V has no BSP-generated equivalent, so the same idea is spelled out: the
# memory is synthesised from a file whose NAME is fixed in the Platform Designer
# system (initializationFileName), and elf2hex has to produce a file of that
# name where Quartus looks for it — the Quartus project directory.
#
# None of the four facts gets a default. Every one of them produces a plausible
# artefact when wrong: a mismatched name synthesises an empty RAM, a wrong base
# or end silently truncates the image, and nothing in the build complains.
NIOSV_MEM_INIT       ?=
NIOSV_MEM_INIT_HEX   ?=
NIOSV_MEM_INIT_BASE  ?=
NIOSV_MEM_INIT_END   ?=
NIOSV_MEM_INIT_WIDTH ?= 32
NIOSV_DIR            := $(BUILD_DIR)/niosv
NIOSV_MEM_INIT_HEX_PATH = $(if $(NIOSV_MEM_INIT),$(QUARTUS_PROJDIR)/$(NIOSV_MEM_INIT_HEX))

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
# QSYS_SEARCH_PATH lists directories holding a project's own _hw.tcl components.
# Platform Designer sees only the vendor library otherwise, and a system that
# instantiates a project component fails with "Component type ... is not in the
# library" — a warning, followed by a generation that reports progress and
# writes a stub with no ports.
#
# The invocation goes through scripts/qsys_generate.sh because --search-path
# must end in a literal '$' to keep the standard library, and that character
# cannot be carried through a define, an $(eval) and a shell reliably. The
# environment variable QSYS_IP_SEARCH_PATH is NOT an alternative: it is ignored.
QSYS_SEARCH_PATH ?=

# Platform Designer COPIES a component's HDL into the generated tree when it
# generates, so a component whose source changed is not rebuilt by editing that
# source: the .qip is still newer than the .qsys and make has nothing to do. The
# design then synthesises the stale copy and the board runs code that is not in
# the repository, which looks exactly like a design that does not work.
#
# The component's _hw.tcl files are found automatically. The HDL they point at
# cannot be — a _hw.tcl may reference any path — so a project with its own
# components adds those sources here.
QSYS_DEPS ?=
_QSYS_DEPS := $(QSYS_DEPS) \
              $(foreach d,$(QSYS_SEARCH_PATH),$(wildcard $(d)/*_hw.tcl))

# A .qsys may be authored by hand or built from a script. Naming the script
# makes it the source of record: the .qsys becomes a build product that is
# rebuilt when the script changes, rather than a file that silently stops
# matching the script it came from.
#
#   QSYS_<system>_SCRIPT := system/build_system.tcl
#
# The script's own save_system decides the file name, which must match the
# QSYS_SYSTEMS entry.

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
# Building the .qsys from its script, when one is declared.
define _qsys_script_rule
$(1): $(2)
	@echo "[QSYS] Building $$(notdir $(1)) from $$(notdir $(2))..."
	$$(call _require_nios2_shell)
	@bash $(TEMPLATE_DIR)scripts/qsys_script.sh "$$(NIOS2_SHELL)" $(2) $$(dir $(1)) \
	    $$(foreach d,$$(QSYS_SEARCH_PATH),$$(abspath $$(d)))
endef
$(foreach q,$(QSYS_SYSTEMS),\
    $(if $(QSYS_$(call _qsys_name,$(q))_SCRIPT),\
        $(eval $(call _qsys_script_rule,$(q),$(QSYS_$(call _qsys_name,$(q))_SCRIPT)))))

define _qsys_rule
$(call _qsys_qip,$(1)): $(1) $$(_QSYS_DEPS)
	@echo "[QSYS] Generating $(call _qsys_name,$(1))..."
	$$(call _require_nios2_shell)
	@$(MKDIR) $(dir $(call _qsys_staged,$(1)))
	@cp $(1) $(call _qsys_staged,$(1))
	@bash $(TEMPLATE_DIR)scripts/qsys_generate.sh "$(NIOS2_SHELL)" \
	    $(call _qsys_staged,$(1)) $(QSYS_LANG) $(QUARTUS_PART) \
	    $(call _qsys_gen,$(1)) $(foreach d,$(QSYS_SEARCH_PATH),$(abspath $(d)))
endef
$(foreach q,$(QSYS_SYSTEMS),$(eval $(call _qsys_rule,$(q))))

qsys: $(QSYS_QIPS)
	@$(if $(QSYS_SYSTEMS),echo "[QSYS] $(words $(QSYS_SYSTEMS)) system(s) generated.",echo "[QSYS] No QSYS_SYSTEMS declared — nothing to do.")

QUARTUS_PROJDIR := $(BUILD_DIR)/quartus_proj
QSF_FILE        := $(QUARTUS_PROJDIR)/$(PROJECT_NAME).qsf
QPF_FILE        := $(QUARTUS_PROJDIR)/$(PROJECT_NAME).qpf
# The QSF sets PROJECT_OUTPUT_DIRECTORY, so the assembler writes here rather
# than beside the project file. Naming the project directory instead makes
# 'make program' fail with "File name ... does not exist" after a build that
# plainly succeeded.
SOF_FILE        := $(QUARTUS_PROJDIR)/output_files/$(PROJECT_NAME).sof

# Project-root path as seen from the Quartus project directory. realpath fails
# when that directory does not exist yet — on the very first build — so the
# fallback must be spelled the same way realpath spells it, without a trailing
# slash, or the first QSF written differs from every later one.
_ROOT_REL := $(shell realpath --relative-to=$(QUARTUS_PROJDIR) . 2>/dev/null || echo "../..")

.PHONY: all synth fit asm sta program cfgmem flash flash-erase qsys nios-bsp nios-apps \
        niosv-bsp niosv-apps _help_quartus

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
	@echo "    cfgmem     Build the configuration-memory image from the .sof"
	@echo "    flash      Write that image to the configuration device"
	@echo "    flash-erase Erase the configuration device and blank-check it"
	@echo "    qsys       Generate HDL from every QSYS_SYSTEMS entry"
	@echo "    nios-bsp   Generate the board support package for each Nios II app"
	@echo "    nios-apps  Build every NIOS_APPS entry into an .elf"
	@echo "    niosv-bsp  Generate the board support package for each Nios V app"
	@echo "    niosv-apps Build every NIOSV_APPS entry into an .elf"

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
#
# .sv is declared SYSTEMVERILOG_FILE, not VERILOG_FILE. The scan groups .v and
# .sv together because most of the framework does not care, but Quartus does:
# read as Verilog-2001, a SystemVerilog source fails on constructs like '0 with
# a syntax error that points at the vendor's file rather than at the assignment
# that mis-declared it.
$(QPF_FILE): | $(QUARTUS_PROJDIR)
	@echo "[QUARTUS] Generating project file: $(QPF_FILE)"
	@( \
	echo "QUARTUS_VERSION = \"21.1\""; \
	echo "PROJECT_REVISION = \"$(PROJECT_NAME)\""; \
	) > $@

$(QSF_FILE): $(VHDL_SRCS) $(V_SRCS) $(QSYS_QIPS) $(NIOS_MEM_INIT_QIP) $(NIOSV_MEM_INIT_HEX_PATH) $(QUARTUS_QSF_EXTRA) $(QUARTUS_SDC) $(QPF_FILE)
	@echo "[QUARTUS] Generating settings file: $(QSF_FILE)"
	@( \
	echo "set_global_assignment -name FAMILY \"$(patsubst \"%\",%,$(QUARTUS_FAMILY))\""; \
	echo "set_global_assignment -name DEVICE $(QUARTUS_PART)"; \
	echo "set_global_assignment -name TOP_LEVEL_ENTITY $(QUARTUS_TOP)"; \
	echo "set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files"; \
	$(foreach f,$(VHDL_SRCS),\
	    echo "set_global_assignment -name VHDL_FILE $(_ROOT_REL)/$(f) -hdl_version $(if $(filter $(f),$(QUARTUS_VHDL93)),VHDL_1993,$(QUARTUS_VHDL_VERSION))";) \
	$(foreach f,$(filter-out %.sv,$(V_SRCS)),\
	    echo "set_global_assignment -name VERILOG_FILE $(_ROOT_REL)/$(f)";) \
	$(foreach f,$(filter %.sv,$(V_SRCS)),\
	    echo "set_global_assignment -name SYSTEMVERILOG_FILE $(_ROOT_REL)/$(f)";) \
	$(foreach f,$(QSYS_QIPS) $(NIOS_MEM_INIT_QIP),\
	    echo "set_global_assignment -name QIP_FILE $(_ROOT_REL)/$(f)";) \
	$(foreach f,$(QUARTUS_SDC),\
	    echo "set_global_assignment -name SDC_FILE $(_ROOT_REL)/$(f)";) \
	$(foreach f,$(QUARTUS_QSF_EXTRA),cat $(f);) \
	) > $@

# ── Guard: generated IP swept into the source list ───────────────────────────
# Platform Designer output belongs under BUILD_DIR. When a system is generated
# into the source tree by hand instead, 'make scan' enumerates all of it, every
# file lands in the project twice — once from the scan, once through the .qip —
# and the two disagree about file types.
#
# The failure that reaches the user is a SystemVerilog syntax error inside
# vendor IP, which sends them looking at the vendor's code. This says what is
# actually wrong.
#
# The test runs in shell rather than in $(if): a make-level conditional whose
# body contains $(foreach) breaks, because the foreach's commas are read as
# $(if) argument separators.
_scanned_ip_dirs = $(sort $(foreach f,$(VHDL_SRCS) $(V_SRCS),\
    $(if $(wildcard $(dir $(f))*.qip),$(patsubst %/,%,$(dir $(f))))))

define _check_scanned_ip
	@dirs="$(_scanned_ip_dirs)"; \
	if [ -n "$$dirs" ]; then \
	    echo "[QUARTUS] error: generated IP found in the scanned source tree:"; \
	    for d in $$dirs; do echo "[QUARTUS]          $$d"; done; \
	    echo "[QUARTUS]"; \
	    echo "[QUARTUS]        Those directories hold a .qip, so they are tool output."; \
	    echo "[QUARTUS]        Scanning them puts every generated file in the project"; \
	    echo "[QUARTUS]        twice and mis-declares .sv sources as Verilog."; \
	    echo "[QUARTUS]"; \
	    echo "[QUARTUS]        Generate into BUILD_DIR (see QSYS_SYSTEMS), or name"; \
	    echo "[QUARTUS]        the directory in SCAN_EXCLUDE and re-run 'make scan'."; \
	    exit 1; \
	fi
endef

# ── Analysis & synthesis ─────────────────────────────────────────────────────
# quartus_map takes the project path and reads the .qsf sitting beside it. It is
# NOT given --source: that flag adds a DESIGN file, so handing it the settings
# file makes Quartus try to elaborate the .qsf and report the real top level as
# undefined. Nor --part: the device belongs in one place, and that is the .qsf.
synth: $(QSYS_QIPS) $(NIOS_MEM_INIT_QIP) $(NIOSV_MEM_INIT_HEX_PATH) $(QSF_FILE)
	$(call _check_scanned_ip)
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

# ── Configuration memory ─────────────────────────────────────────────────────
# 'make cfgmem' builds the flash image from the build's own .sof; 'make flash'
# writes it. Split for the reason the Xilinx side is split: building is cheap
# and repeatable, writing flash is neither.
#
# FLASH_DEVICE HAS NO DEFAULT, deliberately, on the BOOT_ARCH precedent. Name
# the wrong configuration device and quartus_cpf still reports success and still
# writes an image — one the FPGA will not boot from. A default would make that
# the cost of forgetting one line.
#
#   FLASH_FORMAT   jic  JTAG indirect — the FPGA is used as a bridge to write a
#                       configuration device it boots from in AS mode
#                  pof  direct programming of the configuration device
#                  rbf  raw bitstream, for a loader that is not Quartus
#
# Compression matters here beyond build time: an uncompressed image can be most
# of a small configuration device, so a design that needs two images in one
# device may only fit compressed. Measure rather than assume — the ratio depends
# on how full the device is, so it worsens as a design grows.
FLASH_DEVICE      ?=
FLASH_FORMAT      ?= jic
FLASH_COMPRESSION ?= on
FLASH_VERIFY      ?= 1
FLASH_IMAGE       ?= $(QUARTUS_PROJDIR)/output_files/$(PROJECT_NAME).$(FLASH_FORMAT)

_FLASH_OPT := $(QUARTUS_PROJDIR)/cpf_options.txt

# jic needs the FPGA as well as the configuration device: it is the bridge the
# JTAG write goes through. pof addresses the configuration device directly.
_flash_cpf_args = $(strip \
    $(if $(filter jic,$(FLASH_FORMAT)),-d $(FLASH_DEVICE) -s $(QUARTUS_PART)) \
    $(if $(filter pof,$(FLASH_FORMAT)),-d $(FLASH_DEVICE)))

# Verify is on by default and stays a variable only because a format may not
# support it. A flash write that reports success and leaves a board that will
# not boot is the worst thing this could ship.
_flash_pgm_op = $(strip \
    $(if $(filter jic,$(FLASH_FORMAT)),$(if $(filter 1,$(FLASH_VERIFY)),IPV,IP)) \
    $(if $(filter pof,$(FLASH_FORMAT)),$(if $(filter 1,$(FLASH_VERIFY)),BPV,BP)))

define _require_flash_device
	@test -n "$(FLASH_DEVICE)" || { \
	    echo "[QUARTUS] error: FLASH_DEVICE is not set."; \
	    echo "[QUARTUS]        Name the configuration device, e.g. FLASH_DEVICE := EPCQ16."; \
	    echo "[QUARTUS]        It has no default: quartus_cpf accepts a wrong device,"; \
	    echo "[QUARTUS]        reports success, and writes an image that will not boot."; \
	    exit 1; }
endef

$(_FLASH_OPT): | $(QUARTUS_PROJDIR)
	@echo "bitstream_compression=$(FLASH_COMPRESSION)" > $@

cfgmem: $(SOF_FILE) $(_FLASH_OPT)
	@echo "[QUARTUS] Building $(FLASH_FORMAT) image..."
	$(if $(filter rbf,$(FLASH_FORMAT)),,$(call _require_flash_device))
	$(QUARTUS_CPF) -o $(_FLASH_OPT) -c $(_flash_cpf_args) $(SOF_FILE) $(FLASH_IMAGE)
	@echo "[QUARTUS] $(FLASH_IMAGE)"

flash: $(FLASH_IMAGE)
	@echo "[QUARTUS] Writing $(FLASH_IMAGE) to the configuration device..."
	$(call _require_flash_device)
	@test -n "$(_flash_pgm_op)" || { \
	    echo "[QUARTUS] error: FLASH_FORMAT=$(FLASH_FORMAT) is not something quartus_pgm writes."; \
	    echo "[QUARTUS]        Use jic or pof."; exit 1; }
	$(QUARTUS_PGM) -m jtag -o "$(_flash_pgm_op);$(FLASH_IMAGE)"

# Erasing needs an image only because the bridge is built from it: the loader
# that reaches the configuration device is derived from the same file. Nothing
# of the image is written.
#
# R is erase and E is examine. IE is rejected as an illegal option string rather
# than examining something by surprise, but the letter is not the one the word
# starts with. B blank-checks in the same pass, which is the only way to tell an
# erase that worked from one that reported success.
flash-erase: $(FLASH_IMAGE)
	@echo "[QUARTUS] Erasing the configuration device..."
	$(call _require_flash_device)
	$(QUARTUS_PGM) -m jtag -o "IRB;$(FLASH_IMAGE)"

$(FLASH_IMAGE): cfgmem

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
_nios_sopcinfo = $(strip $(if $(NIOS_$(1)_SOPCINFO),$(NIOS_$(1)_SOPCINFO),\
    $(if $(filter 1,$(words $(QSYS_SYSTEMS))),$(call _qsys_spc,$(firstword $(QSYS_SYSTEMS))))))

# A settings pair splits on its FIRST '=' only. Splitting on every one breaks
# any value that contains an equals sign, which BSP compiler-flag settings do —
# hal.make.cflags_user_flags=-march=rv32ia_zicsr would arrive as the value
# "-march" with the rest silently dropped.
_kv_name  = $(firstword $(subst =, ,$(1)))
_kv_value = $(patsubst $(call _kv_name,$(1))=%,%,$(1))

# The .sopcinfo is produced as a side effect of generating a system, whose rule
# has the .qip as its target. A BSP must therefore depend on the .qip; naming
# the .sopcinfo leaves make with no rule for it and the build stops before it
# has generated anything.
_qsys_dep_for = $(strip $(if $(1),$(1),\
    $(if $(filter 1,$(words $(QSYS_SYSTEMS))),$(call _qsys_qip,$(firstword $(QSYS_SYSTEMS))))))

NIOS_ELFS := $(foreach a,$(NIOS_APPS),$(call _nios_elf,$(a)))
NIOS_BSPS := $(foreach a,$(NIOS_APPS),$(call _nios_bsp_dir,$(a))/settings.bsp)

define _nios_rule
$(call _nios_bsp_dir,$(1))/settings.bsp: $(call _qsys_dep_for,$(NIOS_$(1)_SOPCINFO))
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
	    $(foreach kv,$(NIOS_$(1)_BSP_SETTINGS),--set $(call _kv_name,$(kv)) $(call _kv_value,$(kv)))

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

# ── Nios V software ──────────────────────────────────────────────────────────
# NIOSV_APPS names the applications to build. Per application:
#
#   NIOSV_<app>_SRC_DIR      where its sources live                  (required)
#   NIOSV_<app>_SOPCINFO     the system it runs on                   (derived when
#                            exactly one QSYS_SYSTEMS entry is declared)
#   NIOSV_<app>_BSP_TYPE     BSP flavour, defaults to NIOSV_BSP_TYPE
#   NIOSV_<app>_CPU_INSTANCE which processor, when the system has several
#   NIOSV_<app>_BSP_SETTINGS BSP settings as name=value pairs
#   NIOSV_<app>_INCS         extra include directories
#
# There is no per-application compiler-flag variable. The BSP's generated
# toolchain.cmake governs the whole build, application included, so extra flags
# are a BSP setting — hal.make.cflags_user_flags — declared in BSP_SETTINGS.
#
# The Nios V tools are NOT the Nios II tools and are not reached the same way.
# They live in niosv/bin, which nios2_command_shell.sh does not put on PATH,
# and they read QUARTUS_ROOTDIR and SOPC_KIT_NIOS2 from the environment. They
# are invoked by absolute path here for that reason. niosv-shell exists and has
# the same never-returns-when-sourced hazard as its Nios II counterpart.
NIOSV_ROOT     ?= $(ACDS_ROOT)/niosv
NIOSV_BSP_TOOL ?= $(NIOSV_ROOT)/bin/niosv-bsp
NIOSV_APP_TOOL ?= $(NIOSV_ROOT)/bin/niosv-app
NIOSV_ELF2HEX  ?= $(NIOSV_ROOT)/bin/elf2hex
NIOSV_BSP_TYPE ?= hal
NIOSV_CMAKE    ?= cmake

# The compiler name is not a preference. The BSP writes it into its own
# generated toolchain.cmake with a plain set(), which shadows any cache
# override, so a toolchain reachable under any other name will not be used.
NIOSV_CC ?= riscv32-unknown-elf-gcc

# Quartus's own libstdc++ shadows the system one once its environment has been
# sourced, which breaks every non-Quartus binary that links against a newer ABI
# — cmake dies on a missing GLIBCXX before it reaches the compiler. The rule is
# not "cmake needs this"; it is that anything outside quartus/linux64 does.
#
# niosv/bin goes on PATH because the generated build calls back into it: the
# application CMakeLists runs niosv-stack-report unqualified, which fails as a
# bare "command not found" from three levels inside a generated makefile.
NIOSV_ENV = LD_LIBRARY_PATH= SOPC_KIT_NIOS2=$(ACDS_ROOT)/nios2eds \
            PATH="$(NIOSV_ROOT)/bin:$(PATH)"

define _require_niosv_tools
	@for t in "$(NIOSV_BSP_TOOL)" "$(NIOSV_APP_TOOL)" "$(NIOSV_ELF2HEX)"; do \
	    test -x "$$t" || { \
	        echo "[NIOSV] error: Nios V tool not found at $$t"; \
	        echo "[NIOSV]        Set QUARTUS_ROOTDIR (or NIOSV_ROOT) so it resolves."; \
	        exit 1; }; \
	done
	@command -v $(NIOSV_CMAKE) >/dev/null 2>&1 || { \
	    echo "[NIOSV] error: $(NIOSV_CMAKE) not found on PATH."; \
	    echo "[NIOSV]        Nios V applications are built by CMake, not by a"; \
	    echo "[NIOSV]        generated makefile. Set NIOSV_CMAKE or install it."; \
	    exit 1; }
	@command -v $(NIOSV_CC) >/dev/null 2>&1 || { \
	    echo "[NIOSV] error: $(NIOSV_CC) not found on PATH."; \
	    echo "[NIOSV]        The BSP names this compiler in its generated"; \
	    echo "[NIOSV]        toolchain.cmake, so it cannot be substituted by"; \
	    echo "[NIOSV]        setting CMAKE_C_COMPILER. Install a RISC-V"; \
	    echo "[NIOSV]        bare-metal toolchain under this exact prefix, or"; \
	    echo "[NIOSV]        set NIOSV_CC if yours is named differently."; \
	    exit 1; }
endef

_niosv_bsp_dir   = $(NIOSV_DIR)/$(1)/bsp
_niosv_app_dir   = $(NIOSV_DIR)/$(1)/app
_niosv_build_dir = $(NIOSV_DIR)/$(1)/build
_niosv_elf       = $(call _niosv_build_dir,$(1))/$(1).elf

_niosv_sopcinfo = $(strip $(if $(NIOSV_$(1)_SOPCINFO),$(NIOSV_$(1)_SOPCINFO),\
    $(if $(filter 1,$(words $(QSYS_SYSTEMS))),$(call _qsys_spc,$(firstword $(QSYS_SYSTEMS))))))

NIOSV_ELFS := $(foreach a,$(NIOSV_APPS),$(call _niosv_elf,$(a)))
NIOSV_BSPS := $(foreach a,$(NIOSV_APPS),$(call _niosv_bsp_dir,$(a))/settings.bsp)

# --cmd takes its value with an equals sign; the space-separated form is
# rejected as a missing value. Settings are applied by a second --update pass
# because --create writes the defaults after any settings given alongside it.
define _niosv_rule
$(call _niosv_bsp_dir,$(1))/settings.bsp: $(call _qsys_dep_for,$(NIOSV_$(1)_SOPCINFO))
	@echo "[NIOSV] BSP for $(1)..."
	$$(call _require_niosv_tools)
	@test -n "$(call _niosv_sopcinfo,$(1))" || { \
	    echo "[NIOSV] error: NIOSV_$(1)_SOPCINFO is not set and cannot be derived."; \
	    echo "[NIOSV]        Set it, or declare exactly one QSYS_SYSTEMS entry."; \
	    exit 1; }
	@$(MKDIR) $(call _niosv_bsp_dir,$(1))
	@$(NIOSV_ENV) "$(NIOSV_BSP_TOOL)" --create \
	    --sopcinfo=$(call _niosv_sopcinfo,$(1)) \
	    --type=$(if $(NIOSV_$(1)_BSP_TYPE),$(NIOSV_$(1)_BSP_TYPE),$(NIOSV_BSP_TYPE)) \
	    --bsp-dir=$(call _niosv_bsp_dir,$(1)) \
	    $(if $(NIOSV_$(1)_CPU_INSTANCE),--cpu-instance=$(NIOSV_$(1)_CPU_INSTANCE)) \
	    $$@
	$(if $(strip $(NIOSV_$(1)_BSP_SETTINGS)),@$(NIOSV_ENV) "$(NIOSV_BSP_TOOL)" --update \
	    --bsp-dir=$(call _niosv_bsp_dir,$(1)) \
	    $(foreach kv,$(NIOSV_$(1)_BSP_SETTINGS),--cmd="set_setting $(call _kv_name,$(kv)) $(call _kv_value,$(kv))") \
	    $$@)

$(call _niosv_elf,$(1)): $(call _niosv_bsp_dir,$(1))/settings.bsp $(wildcard $(NIOSV_$(1)_SRC_DIR)/*)
	@echo "[NIOSV] Application $(1)..."
	$$(call _require_niosv_tools)
	@test -n "$(NIOSV_$(1)_SRC_DIR)" || { \
	    echo "[NIOSV] error: NIOSV_$(1)_SRC_DIR is not set."; exit 1; }
	@$(MKDIR) $(call _niosv_app_dir,$(1))
	@$(NIOSV_ENV) "$(NIOSV_APP_TOOL)" \
	    --app-dir=$(call _niosv_app_dir,$(1)) \
	    --bsp-dir=$(call _niosv_bsp_dir,$(1)) \
	    --srcs=$(abspath $(NIOSV_$(1)_SRC_DIR)) \
	    --elf-name=$(1).elf \
	    $(foreach d,$(NIOSV_$(1)_INCS),--incs=$(abspath $(d)))
	@$(NIOSV_ENV) $(NIOSV_CMAKE) -G "Unix Makefiles" \
	    -B $(call _niosv_build_dir,$(1)) -S $(call _niosv_app_dir,$(1))
	@$(NIOSV_ENV) $(MAKE) -C $(call _niosv_build_dir,$(1))
endef
$(foreach a,$(NIOSV_APPS),$(eval $(call _niosv_rule,$(a))))

# elf2hex writes into the Quartus project directory because that is where
# Quartus resolves the memory's init_file from: the generated memory carries a
# bare filename, not a path.
$(NIOSV_MEM_INIT_HEX_PATH): $(if $(NIOSV_MEM_INIT),$(call _niosv_elf,$(NIOSV_MEM_INIT))) | $(QUARTUS_PROJDIR)
	@echo "[NIOSV] Memory initialisation from $(NIOSV_MEM_INIT)..."
	$(call _require_niosv_tools)
	@test -n "$(NIOSV_MEM_INIT_HEX)" -a -n "$(NIOSV_MEM_INIT_BASE)" -a -n "$(NIOSV_MEM_INIT_END)" || { \
	    echo "[NIOSV] error: NIOSV_MEM_INIT needs NIOSV_MEM_INIT_HEX, _BASE and _END."; \
	    echo "[NIOSV]        HEX must match the memory's initializationFileName in"; \
	    echo "[NIOSV]        the Platform Designer system; BASE and END are that"; \
	    echo "[NIOSV]        memory's address range. None has a default: each one"; \
	    echo "[NIOSV]        builds a plausible image when wrong."; \
	    exit 1; }
	@$(NIOSV_ENV) "$(NIOSV_ELF2HEX)" $(call _niosv_elf,$(NIOSV_MEM_INIT)) \
	    -o $@ -b $(NIOSV_MEM_INIT_BASE) -e $(NIOSV_MEM_INIT_END) \
	    -w $(NIOSV_MEM_INIT_WIDTH) -r 4

niosv-bsp: $(NIOSV_BSPS)
	@$(if $(NIOSV_APPS),echo "[NIOSV] $(words $(NIOSV_APPS)) BSP(s) ready.",echo "[NIOSV] No NIOSV_APPS declared — nothing to do.")

niosv-apps: $(NIOSV_ELFS)
	@$(if $(NIOSV_APPS),echo "[NIOSV] $(words $(NIOSV_APPS)) application(s) built.",echo "[NIOSV] No NIOSV_APPS declared — nothing to do.")

$(BUILD_DIR)/$(PROJECT_NAME): sta

$(BUILD_DIR):
	$(MKDIR) $@
