# ==============================================================================
# gxx.mk — GNU C++ Compiler toolchain rules
# Handles: .c + .cpp/.cxx/.cc source files → binary
# ==============================================================================

C_OBJS   := $(patsubst %.c,$(BUILD_DIR)/%.o,$(C_SRCS))
CXX_OBJS := $(patsubst %.cc,$(BUILD_DIR)/%.o,\
             $(patsubst %.cxx,$(BUILD_DIR)/%.o,\
             $(patsubst %.cpp,$(BUILD_DIR)/%.o,$(CXX_SRCS))))
ALL_OBJS := $(C_OBJS) $(CXX_OBJS)

DEPS := $(ALL_OBJS:.o=.d)
-include $(DEPS)

CFLAGS   += $(addprefix -I,$(INC_DIRS)) -MMD -MP
CXXFLAGS += $(addprefix -I,$(INC_DIRS)) -MMD -MP

.PHONY: all

all: $(BUILD_DIR)/$(PROJECT_NAME)

# ── Link ──────────────────────────────────────────────────────────────────────
$(BUILD_DIR)/$(PROJECT_NAME): $(ALL_OBJS)
	@echo "[LD]  $@"
	$(CXX) $(LDFLAGS) -o $@ $^ $(LIBS)

# ── Compile ───────────────────────────────────────────────────────────────────
$(BUILD_DIR)/%.o: %.c
	@echo "[CC]  $<"
	@$(MKDIR) $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD_DIR)/%.o: %.cpp
	@echo "[CXX] $<"
	@$(MKDIR) $(dir $@)
	$(CXX) $(CXXFLAGS) -c -o $@ $<

$(BUILD_DIR)/%.o: %.cxx
	@echo "[CXX] $<"
	@$(MKDIR) $(dir $@)
	$(CXX) $(CXXFLAGS) -c -o $@ $<

$(BUILD_DIR)/%.o: %.cc
	@echo "[CXX] $<"
	@$(MKDIR) $(dir $@)
	$(CXX) $(CXXFLAGS) -c -o $@ $<

$(BUILD_DIR):
	$(MKDIR) $@
