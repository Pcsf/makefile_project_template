# ==============================================================================
# project.mk — minimal Nios II example
#
# A soft processor, on-chip memory and a JTAG UART: the smallest system that
# runs C. Every IP in it is free, so this builds on Quartus Prime Lite with no
# licence.
# ==============================================================================

PROJECT_NAME := nios_min_example
BUILD_DIR    := build
TOOLCHAIN    := quartus
SRC_ROOT     := .

# ── Device ────────────────────────────────────────────────────────────────────
QUARTUS_PART   := 10CL025YU256C8G
QUARTUS_FAMILY := "Cyclone 10 LP"
QUARTUS_TOP    := top

# ── Platform Designer ─────────────────────────────────────────────────────────
# Generated HDL enters the Quartus project as a QIP; it is never scanned as
# source. system/build_system.tcl is what produced this .qsys — keep them
# together so the system can be rebuilt without the GUI.
QSYS_SYSTEMS := system/nios_min.qsys
QSYS_LANG    := VERILOG

# ── Nios II software ──────────────────────────────────────────────────────────
# With exactly one system declared, NIOS_hello_SOPCINFO is derived from it.
NIOS_APPS          := hello
NIOS_hello_SRC_DIR := sw/hello

# The small C library and reduced drivers keep the application inside the 32 kB
# of on-chip memory this system has. Without them printf alone does not fit.
NIOS_hello_BSP_SETTINGS := \
    hal.enable_small_c_library=true \
    hal.enable_reduced_device_drivers=true \
    hal.enable_lightweight_device_driver_api=true
