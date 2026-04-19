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

# ── OS detection ──────────────────────────────────────────────────────────────
ifeq ($(OS),Windows_NT)
    HOST_OS     := Windows
    SCAN_SCRIPT := scripts\scan_project.bat
    RMDIR       := cmd /C rmdir /Q /S
    MKDIR       := cmd /C mkdir
    NULL        := NUL
    FIND_MK     := $(shell cmd /C "dir /B /S Makefile.mk 2>NUL | findstr /V ""\make\\ \templates\\ \scripts\\ \build\\ \.git\\"" ")
else
    HOST_OS     := $(shell uname -s)
    SCAN_SCRIPT := scripts/scan_project.sh
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
        2>$(NULL))
endif

# ── Bootstrap: auto-scan on first run when no Makefile.mk exist yet ──────────
ifeq ($(SUBMAKEFILES),)

.DEFAULT_GOAL := _bootstrap
.PHONY: _bootstrap scan help

_bootstrap:
	@echo "[INFO] No Makefile.mk found — running initial project scan..."
	@$(MAKE) --no-print-directory scan
	@echo "[INFO] Scan complete. Starting build..."
	@$(MAKE) --no-print-directory all

scan:
ifeq ($(HOST_OS),Windows)
	@$(SCAN_SCRIPT) "$(SRC_ROOT)"
else
	@bash $(SCAN_SCRIPT) "$(SRC_ROOT)"
endif
	@echo "[INFO] Scan complete."

help:
	@$(MAKE) --no-print-directory -f make/common.mk _help_text

else
# ── Normal build path (Makefile.mk files exist) ───────────────────────────────

# Include all discovered sub-makefiles.
# Each uses $(wildcard …) internally → source lists refresh every invocation.
include $(SUBMAKEFILES)

# Toolchain rules (defines recipe for the primary build target)
include make/$(TOOLCHAIN).mk

# Common utility targets (scan, clean, distclean, help, info)
include make/common.mk

endif
