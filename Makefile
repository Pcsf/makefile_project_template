# ==============================================================================
# Makefile Project Template — Root Makefile
# ==============================================================================
#
# Usage:
#   make              — Scan (if needed) and build
#   make scan         — Scan tree; create/update Makefile.mk in source dirs
#   make clean        — Remove build artefacts
#   make distclean    — Remove build artefacts + all generated Makefile.mk
#   make info         — Show discovered sources and build settings
#   make help         — Show available targets and toolchains
#
# Edit project.mk to configure name, toolchain, flags, etc.
# Supported TOOLCHAIN values: gcc  gxx  ghdl  modelsim  vivado  quartus
# ==============================================================================

# ── Template location (supports use as a git submodule) ──────────────────────
# The template does not have to be the project root: a consuming project can
# keep it as a git submodule and use a one-line root Makefile:
#
#     include makefile_project_template/Makefile
#
# (or invoke 'make -f makefile_project_template/Makefile').  TEMPLATE_DIR is
# this Makefile's directory relative to the working directory, with trailing
# slash — empty when the template itself is the project root.  It must be
# computed before any other makefile is included.
TEMPLATE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
ifeq ($(TEMPLATE_DIR),./)
    TEMPLATE_DIR :=
endif

# When embedded in a consuming project, the template's own tree (example/,
# make/, …) must be excluded from source discovery.  TEMPLATE_EXCLUDE is the
# extra pattern handed to the scan scripts; TEMPLATE_FIND_EXCLUDE the extra
# find(1) filter (recursively expanded — SRC_ROOT is not yet known here).
ifneq ($(TEMPLATE_DIR),)
    TEMPLATE_EXCLUDE      := $(patsubst %/,%,$(TEMPLATE_DIR))
    TEMPLATE_FIND_EXCLUDE  = -not -path "$(SRC_ROOT)/$(TEMPLATE_EXCLUDE)/*"
    TPL_WIN_EXCL          := \$(lastword $(subst /, ,$(TEMPLATE_EXCLUDE)))\\
endif

# ── OS detection ──────────────────────────────────────────────────────────────
ifeq ($(OS),Windows_NT)
    HOST_OS     := Windows
    SCAN_SCRIPT := $(subst /,\,$(TEMPLATE_DIR))scripts\scan_project.bat
    RMDIR       := cmd /C rmdir /Q /S
    MKDIR       := cmd /C mkdir
    NULL        := NUL
    FIND_MK     := $(shell cmd /C "dir /B /S Makefile.mk 2>NUL | findstr /V ""\make\\ \templates\\ \scripts\\ \build\\ \.git\\ $(TPL_WIN_EXCL)"" ")
else
    HOST_OS     := $(shell uname -s)
    SCAN_SCRIPT := $(TEMPLATE_DIR)scripts/scan_project.sh
    RMDIR       := rm -rf
    MKDIR       := mkdir -p
    NULL        := /dev/null
endif

# ── Project configuration ─────────────────────────────────────────────────────
-include project.mk

PROJECT_NAME ?= project
BUILD_DIR    ?= build
TOOLCHAIN    ?= gcc
SRC_ROOT     ?= .

# ── Source variable initialisation (must precede sub-makefile includes) ───────
# Using := so that += in each Makefile.mk expands $(wildcard) immediately,
# giving an up-to-date file list on every make invocation.
C_SRCS    :=
CXX_SRCS  :=
VHDL_SRCS :=
V_SRCS    :=
ASM_SRCS  :=

# ── Discover generated Makefile.mk files ─────────────────────────────────────
ifeq ($(HOST_OS),Windows)
    SUBMAKEFILES := $(FIND_MK)
else
    SUBMAKEFILES := $(shell find $(SRC_ROOT) \
        -name "Makefile.mk" \
        -not -path "*/.git/*" \
        -not -path "*/make/*" \
        -not -path "*/templates/*" \
        -not -path "*/scripts/*" \
        -not -path "*/$(BUILD_DIR)/*" \
        $(TEMPLATE_FIND_EXCLUDE) \
        2>$(NULL))
endif

# ── Bootstrap: auto-scan on first run when no Makefile.mk exist yet ──────────
ifeq ($(SUBMAKEFILES),)

.DEFAULT_GOAL := _bootstrap
.PHONY: _bootstrap

_bootstrap:
	@echo "[INFO] No Makefile.mk found — running initial project scan..."
	@$(MAKE) --no-print-directory scan
	@echo "[INFO] Scan complete. Starting build..."
	@$(MAKE) --no-print-directory all

# Utility targets (scan, clean, distclean, info, help) must work before the
# first scan too; only 'all' needs the generated Makefile.mk files to exist.
include $(TEMPLATE_DIR)make/common.mk

else
# ── Normal build path (Makefile.mk files exist) ───────────────────────────────

# Include all discovered sub-makefiles.
# Each uses .compile_order or $(wildcard) → file lists refresh every invocation.
include $(SUBMAKEFILES)

# ── VHDL_SRCS_DIR: directory-level cross-directory ordering (Layer 1) ─────────
# If VHDL_SRCS_DIR is set in project.mk, VHDL_SRCS is rebuilt from that
# directory list, in order.  Each directory is expanded to its file list using
# the same logic as the per-directory Makefile.mk: .compile_order when present,
# $(wildcard) otherwise.  The user only declares directory order — file
# discovery within each directory remains fully automatic.
#
# All VHDL directories must appear in the list when this variable is set,
# because it replaces the VHDL_SRCS accumulated by the sub-makefiles above.
# Literal '#' for use inside function calls: make >= 4.3 no longer strips
# the backslash of '\#' there, which leaks '\#' into the shell command
# (grep then warns "stray \ before #").  Escaping in a plain variable
# assignment works on every make version, so route the '#' through _HASH.
_HASH := \#
_vhdl_dir_srcs = $(if $(wildcard $(1)/.compile_order),\
    $(addprefix $(1)/,\
        $(shell grep -v '^[[:space:]]*$(_HASH)' '$(1)/.compile_order' \
                | grep -v '^[[:space:]]*$$')),\
    $(wildcard $(1)/*.vhd $(1)/*.vhdl))

ifneq ($(strip $(VHDL_SRCS_DIR)),)
VHDL_SRCS := $(foreach d,$(VHDL_SRCS_DIR),$(call _vhdl_dir_srcs,$(strip $d)))
endif

# Toolchain rules (defines recipe for the primary build target)
include $(TEMPLATE_DIR)make/$(TOOLCHAIN).mk

# Common utility targets (scan, clean, distclean, help, info)
include $(TEMPLATE_DIR)make/common.mk

endif
