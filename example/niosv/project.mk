# ==============================================================================
# project.mk — minimal Nios V/m example
#
# A RISC-V soft processor, on-chip memory and a JTAG UART: the smallest system
# that runs C. Every IP in it is free, so this builds on Quartus Prime Lite with
# no licence. It needs a RISC-V bare-metal toolchain, which no Intel installer
# provides — see mk/README.md.
# ==============================================================================

PROJECT_NAME := niosv_min_example
BUILD_DIR    := build
TOOLCHAIN    := quartus
SRC_ROOT     := .

# ── Device ────────────────────────────────────────────────────────────────────
QUARTUS_PART   := 10CL025YU256C8G
QUARTUS_FAMILY := "Cyclone 10 LP"
QUARTUS_TOP    := top

# ── Platform Designer ─────────────────────────────────────────────────────────
QSYS_SYSTEMS := system/niosv_min.qsys
QSYS_LANG    := VERILOG

# ── Nios V software ───────────────────────────────────────────────────────────
# With exactly one system declared, NIOSV_hello_SOPCINFO is derived from it.
NIOSV_APPS           := hello
NIOSV_hello_SRC_DIR  := sw/hello

# binutils 2.38 moved the CSR instructions out of the base RISC-V I extension.
# The BSP's own crt0.S writes csrw against the -march the IP hardcodes, so under
# any binutils at or past that release it fails to assemble. This setting is
# emitted after that -march and GCC takes the last one, which fixes it without
# editing a generated file. rv32ia is Nios V/m with 32 registers; a 16-register
# core is rv32ea.
NIOSV_hello_BSP_SETTINGS := \
    hal.make.cflags_user_flags=-march=rv32ia_zicsr \
    hal.enable_reduced_device_drivers=true \
    hal.enable_lightweight_device_driver_api=true

# Bake the program into the FPGA image. The name must match the on-chip memory's
# initializationFileName in the Platform Designer system, and the range must be
# that memory's — a mismatch synthesises an empty RAM and the processor fetches
# zeros, with nothing in the build complaining.
NIOSV_MEM_INIT      := hello
NIOSV_MEM_INIT_HEX  := niosv_min_ram.hex
NIOSV_MEM_INIT_BASE := 0x0
NIOSV_MEM_INIT_END  := 0x7FFF
