# ==============================================================================
# common.mk — Utility targets shared by all toolchains
# Included by the root Makefile after toolchain-specific rules.
# ==============================================================================

# ── Literals ─────────────────────────────────────────────────────────────────
# make has no way to write a bare space or comma inside a $(subst), so both are
# built here and used by any toolchain that has to join a list.
empty :=
space := $(empty) $(empty)
comma := ,

# ── Verdict ───────────────────────────────────────────────────────────────────
# The toolchain-neutral verdict for `make test`, used by any toolchain whose
# runner does not report failure through its exit status. Kept in its own file
# so it can be exercised standalone by tests/verdict.sh.
include $(TEMPLATE_DIR)make/verdict.mk

.PHONY: scan clean distclean help info test test-report _help_text _help_workflow

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

# ── test ──────────────────────────────────────────────────────────────────────
# The framework's contract target. `make test` means one thing everywhere: it
# ran the project's checks, and its exit status is the truth about them.
#
# A toolchain whose runner reports failure honestly needs nothing beyond
# TEST_CMD, declared by the project. One whose runner does not — it always exits
# zero, or it reports only in its transcript — defines its own `test` recipe and
# sets TOOLCHAIN_HAS_TEST := 1, which suppresses this generic one. That is the
# single extension point; nothing else here changes when a language is added.
#
# No TEST_CMD and no toolchain recipe is a refusal, never a pass. A project with
# no tests must say so by failing, because a silent zero here is indistinguishable
# from a suite that ran and passed.
ifneq ($(strip $(TOOLCHAIN_HAS_TEST)),1)
test:
ifeq ($(strip $(TEST_CMD)),)
	@echo "[TEST] No tests configured for toolchain '$(TOOLCHAIN)'."
	@echo "[TEST] Set TEST_CMD in project.mk to the command that runs them,"
	@echo "[TEST] or select a toolchain that defines its own test recipe."
	@exit 1
else
	@$(MAKE) --no-print-directory
	@echo "[TEST] $(TEST_CMD)"
	@if [ -n "$(strip $(TEST_LOG))" ]; then \
	    mkdir -p "$(dir $(abspath $(TEST_LOG)))"; \
	    $(TEST_CMD) > "$(abspath $(TEST_LOG))" 2>&1; rc=$$?; \
	    cat "$(abspath $(TEST_LOG))"; \
	    if [ $$rc -ne 0 ]; then \
	        echo "[TEST] FAILED — TEST_CMD exited $$rc."; exit $$rc; \
	    fi; \
	else \
	    $(TEST_CMD) || { echo "[TEST] FAILED — TEST_CMD exited non-zero."; exit 1; }; \
	fi
	$(if $(strip $(TEST_LOG)),$(if $(or $(strip $(TEST_FAIL_PATTERN)),$(strip $(TEST_PASS_PATTERN))),$(call _test_verdict,TEST)))
	@echo "[TEST] PASSED."
endif
endif

# ── test-report ───────────────────────────────────────────────────────────────
# `make test` answers one question for the whole suite. `test-report` answers it
# per test case, by writing JUnit XML to a known path. That is what lets a tool
# outside the build bind one requirement to one named test rather than to the
# whole run.
#
# The framework does not know how the report is produced, and must not: a VHDL
# test framework, a Python one, or a language's own runner all emit JUnit XML.
# The project declares the command; the framework fixes only the path and checks
# that something was actually written there.
#
# Independent of `test` on purpose. A toolchain may implement one, both, or
# neither, and a report generator usually drives its own compilation, so this
# does not build first.
TEST_REPORT     ?= $(BUILD_DIR)/test-results.xml
TEST_REPORT_CMD ?=

test-report:
ifeq ($(strip $(TEST_REPORT_CMD)),)
	@echo "[REPORT] No report command configured."
	@echo "[REPORT] Set TEST_REPORT_CMD in project.mk to a command that writes"
	@echo "[REPORT] JUnit XML to $$TEST_REPORT."
	@exit 1
else
	@$(MKDIR) $(dir $(abspath $(TEST_REPORT)))
	@rm -f "$(abspath $(TEST_REPORT))"
	@echo "[REPORT] $(TEST_REPORT_CMD)"
	@TEST_REPORT="$(abspath $(TEST_REPORT))" $(TEST_REPORT_CMD); rc=$$?; \
	if [ ! -s "$(abspath $(TEST_REPORT))" ]; then \
	    echo "[REPORT] FAILED — no report at $(TEST_REPORT); the command wrote nothing."; \
	    exit 1; \
	fi; \
	if ! grep -q "<testsuite" "$(abspath $(TEST_REPORT))"; then \
	    echo "[REPORT] FAILED — $(TEST_REPORT) is not JUnit XML."; \
	    exit 1; \
	fi; \
	echo "[REPORT] $(TEST_REPORT)"; \
	exit $$rc
endif

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
	@echo "  Named VHDL libraries ($(words $(VHDL_LIBS))):"
	@$(foreach lib,$(VHDL_LIBS),echo "    $(lib) ($(words $(VHDL_LIB_$(lib)_SRCS)) source(s); deps: $(or $(VHDL_LIB_$(lib)_DEPS),none))";)
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
