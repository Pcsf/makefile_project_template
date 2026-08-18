# ==============================================================================
# project.mk — User project configuration
# Edit this file; never edit the generated Makefile.mk files.
# ==============================================================================

# Output artefact name (binary, library, or simulation target)
PROJECT_NAME := my_project

# Build output directory
BUILD_DIR := build

# Toolchain selection — uncomment exactly one:
#   gcc       GNU C Compiler          (.c)
#   gxx       GNU C++ Compiler        (.cpp .cxx .cc)
#   ghdl      GHDL VHDL simulator     (.vhd .vhdl)
#   modelsim  ModelSim / QuestaSim    (.vhd .vhdl .v .sv)
#   vivado    Xilinx Vivado           (.vhd .v .sv .xdc)
#   quartus   Intel/Altera Quartus    (.vhd .v .sv .qsf)
TOOLCHAIN := gcc

# Directory where the scan script starts (default: project root ".")
SRC_ROOT := .

# Directories the scan must NOT descend into, relative to SRC_ROOT. Use this for
# a vendored sub-project that has its own project.mk — without it, its sources
# are swept into this build.
# SCAN_EXCLUDE := path/to/subproject

# This repo's own Nios II example is a self-contained project; keep its sources
# out of the template's default build.
SCAN_EXCLUDE := example/nios2

# ── VHDL_SRCS_DIR: directory-level compilation order (Layer 1) ───────────────
# VHDL compilation order matters: packages must precede their users, entities
# must precede their instantiators.  Three layers handle this:
#
#   Layer 3 (automatic): ghdl.mk / modelsim.mk run a silent pre-pass that
#     pre-populates the work library.  Handles most designs with zero effort.
#
#   Layer 2 (semi-automatic): 'make scan' creates a per-directory .compile_order
#     listing files alphabetically as a starting point.  Edit it once to set the
#     correct within-directory order.  Never overwritten by subsequent scans.
#
#   Layer 1 (this variable): controls cross-directory order when Layers 2+3
#     are not enough.  List directories in compilation order — file discovery
#     within each directory is still fully automatic (via its .compile_order or
#     $(wildcard)).  All VHDL directories must be listed when this is set.
#
# Uncomment and populate when cross-directory ordering matters:
# VHDL_SRCS_DIR := \
#     hdl/lib      \
#     hdl/rtl      \
#     hdl/top

# ── GNU C / C++ settings ──────────────────────────────────────────────────────
CC       := gcc
CXX      := g++
AR       := ar
CFLAGS   := -Wall -Wextra -O2 -g
CXXFLAGS := -Wall -Wextra -O2 -g -std=c++17
LDFLAGS  :=
LIBS     :=
# Space-separated list of extra include directories
INC_DIRS :=

# ── GHDL settings ─────────────────────────────────────────────────────────────
GHDL       := ghdl
GHDL_STD   := 08         # VHDL standard: 87 | 93 | 00 | 02 | 08
GHDL_FLAGS :=
GHDL_TOP   := top         # Top-level entity for elaboration/simulation
GHDL_SIM_FLAGS :=         # Extra flags passed to the simulation step

# ── ModelSim / QuestaSim settings ─────────────────────────────────────────────
VLIB      := vlib
VMAP      := vmap
VCOM      := vcom
VLOG      := vlog
VSIM      := vsim
VSIM_WORK := work
VSIM_TOP  := top
VSIM_FLAGS :=

# ── Xilinx Vivado settings ────────────────────────────────────────────────────
VIVADO      := vivado
VIVADO_PART := xc7a35tcpg236-1   # Target device part number
VIVADO_TOP  := top                # Top-level design unit
VIVADO_XDC  :=                    # Constraints file(s), space-separated

# ── Xilinx boot images (bootgen / program_flash) ──────────────────────────────
# Only needed when the project produces a BOOT.BIN. Each BOOT_IMAGES entry names
# a .bif and the flash offset it is written to. BOOT_FLASH_IMAGES is the subset
# 'make flash-boot' writes over JTAG — normally just the recovery image, since
# flashing a field-updatable one by accident is what this split prevents.
#
# BOOT_ARCH HAS NO DEFAULT, deliberately. bootgen does not check -arch against
# the .bif: hand it the wrong family and it reports "Bootimage generated
# successfully", exits 0, and writes an image the BootROM refuses. A default
# would make that the cost of forgetting one line, so 'make boot-image' refuses
# to run until this is set.
#
# BOOT_ARCH := zynq                 # zynq | zynqmp | versal
#
# BOOT_IMAGES        := golden update
# BOOT_golden_BIF    := boot/golden.bif
# BOOT_golden_OFFSET := 0x000000
# BOOT_update_BIF    := boot/update.bif
# BOOT_update_OFFSET := 0x700000
# BOOT_FLASH_IMAGES  := golden
#
# BOOT_FLASH_TYPE      := qspi_single  # program_flash -flash_type
# BOOT_FSBL            :=              # defaults to the platform's generated
#                                      # boot ELF, discovered per device family
# BOOT_HW_SERVER_RESET := 0            # keep a hw_server you run yourself

# ── Intel/Altera Quartus Prime settings ───────────────────────────────────────
QUARTUS_SH   := quartus_sh
QUARTUS_MAP  := quartus_map
QUARTUS_FIT  := quartus_fit
QUARTUS_ASM  := quartus_asm
QUARTUS_STA  := quartus_sta
QUARTUS_PART := EP4CE6E22C8       # Target device
QUARTUS_TOP  := top               # Top-level entity
QUARTUS_FAMILY := "Cyclone IV E"
QUARTUS_PGM  := quartus_pgm

# ── Platform Designer (Qsys) ──────────────────────────────────────────────────
# Only needed when the design contains a Platform Designer system. Each entry is
# a .qsys file; 'make qsys' generates its HDL under BUILD_DIR and the QSF picks
# the result up as a QIP_FILE. Generated HDL is never scanned as source.
#
# The system is copied into BUILD_DIR before generation, because qsys-generate
# writes the .sopcinfo next to the .qsys it is handed — generating in place
# drops a large generated file into the source tree on every build.
#
# QSYS_SYSTEMS := system/my_system.qsys
# QSYS_LANG    := VERILOG            # VERILOG | VHDL

# ── Nios II software ──────────────────────────────────────────────────────────
# Only needed when a Platform Designer system contains a Nios II processor.
# 'make nios-bsp' generates the board support package and 'make nios-apps'
# builds each application into an .elf, both under BUILD_DIR.
#
# NIOS_<app>_SOPCINFO is derived when exactly ONE system is declared. With
# several it is required: an application built against the wrong memory map
# links cleanly and then does not run, so the framework will not guess.
#
# NIOS_APPS          := hello
# NIOS_hello_SRC_DIR := sw/hello
# NIOS_hello_SOPCINFO := $(BUILD_DIR)/qsys/my_system/my_system.sopcinfo
# NIOS_BSP_TYPE      := hal          # per-app override: NIOS_hello_BSP_TYPE
# NIOS_hello_BSP_SETTINGS := \
#     hal.enable_small_c_library=true \
#     hal.enable_reduced_device_drivers=true
# NIOS_hello_CFLAGS  := -O2
#
# NIOS2_SHELL — the nios2_command_shell.sh wrapper. Derived from
# QUARTUS_ROOTDIR, which the Quartus environment exports. Set it only when the
# Nios II tools live somewhere the derivation cannot reach.
# NIOS2_SHELL := /path/to/nios2eds/nios2_command_shell.sh
