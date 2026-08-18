# Minimal Nios V/m system: a soft processor, on-chip memory and a JTAG UART.
# Every IP here is free, so it builds on Quartus Prime Lite without a licence.
#
# The wiring follows the vendor's own hello_world example design, shipped in
# the IP under example_design/. Three connections there are easy to miss and
# produce a system that generates cleanly and does not run:
#
#   dm_agent        the debug module, addressed by both managers
#   timer_sw_agent  the machine timer and software interrupt, which the HAL
#                   needs mapped even when nothing uses a timer
#   platform_irq_rx the interrupt receiver — Nios V has no separate irq port
#
# Nios V has no exception-vector parameter. RISC-V takes its trap vector from
# mtvec, written by the runtime, so only the reset vector is set.
package require -exact qsys 16.0

create_system niosv_min
set_project_property DEVICE_FAMILY {Cyclone 10 LP}
set_project_property DEVICE {10CL025YU256C8G}

add_instance clock_in altera_clock_bridge
set_instance_parameter_value clock_in EXPLICIT_CLOCK_RATE {50000000.0}

add_instance reset_in altera_reset_bridge
set_instance_parameter_value reset_in SYNCHRONOUS_EDGES {none}

add_instance cpu intel_niosv_m
set_instance_parameter_value cpu enableDebug {1}
set_instance_parameter_value cpu numGpr {32}
set_instance_parameter_value cpu resetSlave {ram.s1}
set_instance_parameter_value cpu resetOffset {0}

# initializationFileName is the contract between this system and elf2hex: the
# memory is synthesised from a file of that name, and the software build has to
# produce one. Without useNonDefaultInitFile the tool picks its own name and the
# two silently disagree.
add_instance ram altera_avalon_onchip_memory2
set_instance_parameter_value ram memorySize {32768}
set_instance_parameter_value ram initMemContent {1}
set_instance_parameter_value ram useNonDefaultInitFile {1}
set_instance_parameter_value ram initializationFileName {niosv_min_ram.hex}

add_instance jtag_uart altera_avalon_jtag_uart

add_connection clock_in.out_clk/cpu.clk
add_connection clock_in.out_clk/ram.clk1
add_connection clock_in.out_clk/jtag_uart.clk

add_connection reset_in.out_reset/cpu.reset
add_connection reset_in.out_reset/ram.reset1
add_connection reset_in.out_reset/jtag_uart.reset

add_connection cpu.instruction_manager/ram.s1
set_connection_parameter_value cpu.instruction_manager/ram.s1 baseAddress {0x00000000}
add_connection cpu.instruction_manager/cpu.dm_agent
set_connection_parameter_value cpu.instruction_manager/cpu.dm_agent baseAddress {0x00080000}

add_connection cpu.data_manager/ram.s1
set_connection_parameter_value cpu.data_manager/ram.s1 baseAddress {0x00000000}
add_connection cpu.data_manager/cpu.dm_agent
set_connection_parameter_value cpu.data_manager/cpu.dm_agent baseAddress {0x00080000}
add_connection cpu.data_manager/cpu.timer_sw_agent
set_connection_parameter_value cpu.data_manager/cpu.timer_sw_agent baseAddress {0x00090000}
add_connection cpu.data_manager/jtag_uart.avalon_jtag_slave
set_connection_parameter_value cpu.data_manager/jtag_uart.avalon_jtag_slave baseAddress {0x00090078}

add_connection cpu.platform_irq_rx/jtag_uart.irq

add_interface clk clock sink
set_interface_property clk EXPORT_OF clock_in.in_clk
add_interface reset reset sink
set_interface_property reset EXPORT_OF reset_in.in_reset

save_system {niosv_min.qsys}
