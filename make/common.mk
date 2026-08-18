# ==============================================================================
# common.mk — Utility targets shared by all toolchains
# Included by the root Makefile after toolchain-specific rules.
# ==============================================================================

.PHONY: scan clean distclean help info _help_text _help_workflow

# ── scan ──────────────────────────────────────────────────────────────────────
# Re-run the scan script to pick up new source directories.
# Within existing directories, $(wildcard) in each Makefile.mk already
# refreshes the source list on every make invocation — no rescan needed.
scan:
ifeq ($(HOST_OS),Windows)
	@$(SCAN_SCRIPT) "$(SRC_ROOT)" $(if $(TEMPLATE_EXCLUDE),"$(TEMPLATE_EXCLUDE)") $(foreach d,$(SCAN_EXCLUDE),"$(d)")
else
	@bash $(SCAN_SCRIPT) "$(SRC_ROOT)" $(if $(TEMPLATE_EXCLUDE),"$(TEMPLATE_EXCLUDE)") $(foreach d,$(SCAN_EXCLUDE),"$(d)")
endif
	@echo "[INFO] Scan complete. Re-run 'make' to rebuild with any new sources."

# ── clean ─────────────────────────────────────────────────────────────────────
clean:
	@echo "[CLEAN] Removing $(BUILD_DIR)/"
	@$(RMDIR) $(BUILD_DIR) 2>$(NULL) || true

# ── distclean ─────────────────────────────────────────────────────────────────
distclean: clean
	@echo "[DISTCLEAN] Removing generated Makefile.mk files..."
ifeq ($(HOST_OS),Windows)
	@FOR /R "$(SRC_ROOT)" %%F IN (Makefile.mk) DO ( \
	    echo %%F | findstr /V "\make\ \templates\ \scripts\ " >NUL && DEL /Q "%%F" \
	)
else
	@find $(SRC_ROOT) -name "Makefile.mk" \
	    -not -path "*/make/*" \
	    -not -path "*/templates/*" \
	    -not -path "*/scripts/*" \
	    $(TEMPLATE_FIND_EXCLUDE) \
	    $(SCAN_FIND_EXCLUDE) \
	    -delete
endif
	@echo "[DISTCLEAN] Done."

# ── info ──────────────────────────────────────────────────────────────────────
info:
	@echo ""
	@echo "  Project   : $(PROJECT_NAME)"
	@echo "  Toolchain : $(TOOLCHAIN)"
	@echo "  Build dir : $(BUILD_DIR)"
	@echo "  Host OS   : $(HOST_OS)"
	@echo ""
	@echo "  C sources ($(words $(C_SRCS))):"
	@$(foreach f,$(C_SRCS),echo "    $(f)";)
	@echo "  C++ sources ($(words $(CXX_SRCS))):"
	@$(foreach f,$(CXX_SRCS),echo "    $(f)";)
	@echo "  VHDL sources ($(words $(VHDL_SRCS))):"
	@$(foreach f,$(VHDL_SRCS),echo "    $(f)";)
	@echo "  Verilog/SV sources ($(words $(V_SRCS))):"
	@$(foreach f,$(V_SRCS),echo "    $(f)";)
	@echo "  ASM sources ($(words $(ASM_SRCS))):"
	@$(foreach f,$(ASM_SRCS),echo "    $(f)";)
	@echo ""

# ── help ──────────────────────────────────────────────────────────────────────
#
# Split so the selected toolchain can list its OWN targets between the core list
# and the workflow notes. Each make/<toolchain>.mk sets TOOLCHAIN_HELP_TARGET to
# a target it defines; one that sets nothing contributes nothing, and the
# pre-scan bootstrap path — which includes this file with no toolchain module at
# all — still gets the core list.
#
# A hook rather than a list of toolchain targets written out here: the whole
# point of the split is that this file knows nothing about any particular
# vendor, and a synth/program/flash target named in here would be wrong the
# moment a toolchain without one is selected.
help: _help_text $(TOOLCHAIN_HELP_TARGET) _help_workflow

_help_text:
	@echo ""
	@echo "  Makefile Project Template"
	@echo "  ════════════════════════════════════════════════════"
	@echo "  Targets:"
	@echo "    all        Build project (auto-scans on first run)"
	@echo "    scan       Scan source tree; create/update Makefile.mk"
	@echo "    clean      Remove build output"
	@echo "    distclean  Remove build output + all Makefile.mk files"
	@echo "    info       Show discovered sources and settings"
	@echo "    help       Show this message"
	@echo ""
	@echo "  Toolchain (set TOOLCHAIN=<name> or edit project.mk):"
	@echo "    gcc        GNU C Compiler"
	@echo "    gxx        GNU C++ Compiler"
	@echo "    ghdl       GHDL VHDL Simulator"
	@echo "    modelsim   ModelSim / QuestaSim HDL Simulator"
	@echo "    vivado     Xilinx Vivado (synthesis + implementation)"
	@echo "    quartus    Intel/Altera Quartus Prime"

_help_workflow:
	@echo ""
	@echo "  Workflow:"
	@echo "    1. Edit project.mk (set PROJECT_NAME, TOOLCHAIN, flags)"
	@echo "    2. Add source files anywhere under SRC_ROOT"
	@echo "    3. Run 'make' — scans automatically on first run"
	@echo "    4. New files in existing dirs are picked up automatically."
	@echo "       New directories require 'make scan' to be re-run."
	@echo ""
