# ==============================================================================
# quartus.mk — Intel/Altera Quartus Prime toolchain rules
# Handles: VHDL / Verilog / SV → synthesis → fit → assembly → STA → .sof
#
# ── Compilation order strategy ────────────────────────────────────────────────
# Quartus's analysis & synthesis (quartus_map) reads all sources specified in
# the QSF.  For VHDL, the file order in QSF matters for older VHDL standards;
# VHDL-2008 in Quartus is more tolerant but still benefits from correct order.
# VHDL_SRCS order is controlled by per-directory .compile_order files (Layer 2)
# or VHDL_SRCS_DIR in project.mk (Layer 1 — list directories in order).
# ==============================================================================

QUARTUS_PROJDIR := $(BUILD_DIR)/quartus_proj
QSF_FILE        := $(QUARTUS_PROJDIR)/$(PROJECT_NAME).qsf
QPF_FILE        := $(QUARTUS_PROJDIR)/$(PROJECT_NAME).qpf
SOF_FILE        := $(QUARTUS_PROJDIR)/$(PROJECT_NAME).sof

_ROOT_REL := $(shell realpath --relative-to=$(QUARTUS_PROJDIR) . 2>/dev/null || echo "../../")

.PHONY: all synth fit asm sta program

all: sta

$(QUARTUS_PROJDIR):
	$(MKDIR) $(QUARTUS_PROJDIR)

# ── Generate Quartus project files ────────────────────────────────────────────
# VHDL_FILE assignments are written in VHDL_SRCS order, which reflects the
# .compile_order files produced by 'make scan'.
$(QPF_FILE): | $(QUARTUS_PROJDIR)
	@echo "[QUARTUS] Generating project file: $(QPF_FILE)"
	@( \
	echo "QUARTUS_VERSION = \"21.1\""; \
	echo "PROJECT_REVISION = \"$(PROJECT_NAME)\""; \
	) > $@

$(QSF_FILE): $(VHDL_SRCS) $(V_SRCS) $(QPF_FILE)
	@echo "[QUARTUS] Generating settings file: $(QSF_FILE)"
	@( \
	echo "set_global_assignment -name FAMILY $(QUARTUS_FAMILY)"; \
	echo "set_global_assignment -name DEVICE $(QUARTUS_PART)"; \
	echo "set_global_assignment -name TOP_LEVEL_ENTITY $(QUARTUS_TOP)"; \
	echo "set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files"; \
	$(foreach f,$(VHDL_SRCS),\
	    echo "set_global_assignment -name VHDL_FILE $(_ROOT_REL)/$(f)";) \
	$(foreach f,$(V_SRCS),\
	    echo "set_global_assignment -name VERILOG_FILE $(_ROOT_REL)/$(f)";) \
	) > $@

# ── Analysis & synthesis ─────────────────────────────────────────────────────
synth: $(QSF_FILE)
	@echo "[QUARTUS] Analysis and synthesis..."
	$(QUARTUS_MAP) --read_settings_files=on --write_settings_files=off \
	    --part=$(QUARTUS_PART) \
	    --source=$(QSF_FILE) \
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
	quartus_pgm -m jtag -o "p;$(SOF_FILE)"

$(BUILD_DIR)/$(PROJECT_NAME): sta

$(BUILD_DIR):
	$(MKDIR) $@
