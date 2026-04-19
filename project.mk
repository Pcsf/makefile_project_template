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

# ── VHDL compilation order — Layer 1 global override ─────────────────────────
# VHDL compilation order matters: packages must precede their users, entities
# must precede their instantiators.  Three layers handle this automatically:
#
#   Layer 3 (automatic): ghdl.mk / modelsim.mk run a silent pre-pass that
#     pre-populates the work library so the real pass finds all dependencies
#     already compiled.  Handles most designs with no user action.
#
#   Layer 2 (semi-automatic): 'make scan' creates a .compile_order file in each
#     VHDL directory listing files alphabetically.  Edit it to set the correct
#     order.  The file is never overwritten by subsequent 'make scan' runs.
#     Add new files to it manually when you create them.
#
#   Layer 1 (manual — this block): for cross-directory ordering that cannot be
#     expressed per-directory.  If set, VHDL_SRCS overrides all auto-discovery.
#     List ALL .vhd/.vhdl files across the whole project in exact order.
#
# Uncomment and populate only when Layers 2+3 are insufficient:
# VHDL_SRCS := \
#     lib/utils_pkg.vhd    \
#     rtl/my_entity.vhd    \
#     top/top.vhd

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

# ── Intel/Altera Quartus Prime settings ───────────────────────────────────────
QUARTUS_SH   := quartus_sh
QUARTUS_MAP  := quartus_map
QUARTUS_FIT  := quartus_fit
QUARTUS_ASM  := quartus_asm
QUARTUS_STA  := quartus_sta
QUARTUS_PART := EP4CE6E22C8       # Target device
QUARTUS_TOP  := top               # Top-level entity
QUARTUS_FAMILY := "Cyclone IV E"
