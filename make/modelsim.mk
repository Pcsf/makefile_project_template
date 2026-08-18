# ==============================================================================
# modelsim.mk — ModelSim / QuestaSim HDL simulator toolchain rules
# Handles: .vhd/.vhdl + .v/.sv → compile → simulate
#
# ── Compilation order strategy ────────────────────────────────────────────────
# Same three-layer defence as ghdl.mk:
#   Layer 1 – VHDL_SRCS_DIR in project.mk: directories in compilation order;
#              file lists within each directory remain auto-managed
#   Layer 2 – per-directory .compile_order files (created by 'make scan')
#   Layer 3 – silent pre-pass below (auto-handles most ordering issues)
#
# vcom fails fast on an unresolved reference but succeeds if the referenced
# unit is already in the work library from a previous run.  The pre-pass
# compiles as many files as possible so the real pass finds all dependencies.
# ==============================================================================

# ── Tool names ───────────────────────────────────────────────────────────────
# Defaulted rather than required. Without a default an unset variable expands to
# nothing and the recipe runs its own first flag as the command, which fails as
# "not found" and points at the flag rather than at the missing tool.
VSIM ?= vsim
VCOM ?= vcom
VLOG ?= vlog
VLIB ?= vlib

VSIM_WORKDIR := $(BUILD_DIR)/modelsim_work

.PHONY: all compile simulate _help_modelsim

# Listed by 'make help' — see the TOOLCHAIN_HELP_TARGET hook in common.mk.
TOOLCHAIN_HELP_TARGET := _help_modelsim

_help_modelsim:
	@echo ""
	@echo "  ModelSim targets:"
	@echo "    compile    Compile the sources into the work library"
	@echo "    simulate   Run VSIM_TOP — this is what 'all' builds"

all: simulate

$(VSIM_WORKDIR):
	$(MKDIR) $(VSIM_WORKDIR)

# ── Create / map work library ─────────────────────────────────────────────────
$(VSIM_WORKDIR)/$(VSIM_WORK)/_info: | $(VSIM_WORKDIR)
	@echo "[MSIM] Creating work library..."
	$(VLIB) $(VSIM_WORKDIR)/$(VSIM_WORK)
	$(VMAP) $(VSIM_WORK) $(VSIM_WORKDIR)/$(VSIM_WORK)

# ── Compile ───────────────────────────────────────────────────────────────────
compile: $(VSIM_WORKDIR)/$(VSIM_WORK)/_info
ifneq ($(strip $(VHDL_SRCS)),)
	@echo "[MSIM] VHDL pre-pass ($(words $(VHDL_SRCS)) file(s), errors silenced)..."
	@$(foreach f,$(VHDL_SRCS),\
	    $(VCOM) -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	            -work $(VSIM_WORK) -$(GHDL_STD) $(f) 2>/dev/null;) true
	@echo "[MSIM] VHDL final pass:"
	@$(foreach f,$(VHDL_SRCS),\
	    printf '  [VCOM] %s\n' '$(f)' && \
	    $(VCOM) -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	            -work $(VSIM_WORK) -$(GHDL_STD) $(f) || \
	    { echo '[MSIM] FAILED on: $(f)'; \
	      echo '[MSIM] Fix: check .compile_order or set VHDL_SRCS in project.mk'; \
	      exit 1; };)
endif
ifneq ($(strip $(V_SRCS)),)
	@echo "[MSIM] Verilog/SV pre-pass ($(words $(V_SRCS)) file(s), errors silenced)..."
	@$(foreach f,$(V_SRCS),\
	    $(VLOG) -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	            -work $(VSIM_WORK) $(f) 2>/dev/null;) true
	@echo "[MSIM] Verilog/SV final pass:"
	@$(foreach f,$(V_SRCS),\
	    printf '  [VLOG] %s\n' '$(f)' && \
	    $(VLOG) -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	            -work $(VSIM_WORK) $(f) || \
	    { echo '[MSIM] FAILED on: $(f)'; exit 1; };)
endif

# ── Simulate ─────────────────────────────────────────────────────────────────
simulate: compile
	@echo "[MSIM] Simulating '$(VSIM_WORK).$(VSIM_TOP)'..."
	$(VSIM) -c $(VSIM_FLAGS) \
	    -modelsimini $(VSIM_WORKDIR)/modelsim.ini \
	    -do "run -all; quit -f" \
	    $(VSIM_WORK).$(VSIM_TOP)

$(BUILD_DIR)/$(PROJECT_NAME): simulate

$(BUILD_DIR):
	$(MKDIR) $@
