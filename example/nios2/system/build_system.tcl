package require -exact qsys 16.0

create_system nios_min
set_project_property DEVICE_FAMILY {Cyclone 10 LP}
set_project_property DEVICE {10CL025YU256C8G}

add_instance clk clock_source
set_instance_parameter_value clk {clockFrequency} {50000000}

add_instance cpu altera_nios2_gen2
set_instance_parameter_value cpu {impl} {Tiny}
set_instance_parameter_value cpu {resetSlave} {mem.s1}
set_instance_parameter_value cpu {resetOffset} {0}
set_instance_parameter_value cpu {exceptionSlave} {mem.s1}
set_instance_parameter_value cpu {exceptionOffset} {32}

add_instance mem altera_avalon_onchip_memory2
set_instance_parameter_value mem {memorySize} {32768}
set_instance_parameter_value mem {initMemContent} {1}

add_instance jtag_uart altera_avalon_jtag_uart

add_connection clk.clk cpu.clk
add_connection clk.clk mem.clk1
add_connection clk.clk jtag_uart.clk
add_connection clk.clk_reset cpu.reset
add_connection clk.clk_reset mem.reset1
add_connection clk.clk_reset jtag_uart.reset

add_connection cpu.data_master mem.s1
add_connection cpu.instruction_master mem.s1
add_connection cpu.data_master jtag_uart.avalon_jtag_slave
add_connection cpu.data_master cpu.debug_mem_slave
add_connection cpu.instruction_master cpu.debug_mem_slave
add_connection cpu.irq jtag_uart.irq
add_connection cpu.debug_reset_request mem.reset1

set_connection_parameter_value cpu.data_master/mem.s1 baseAddress {0x0000}
set_connection_parameter_value cpu.instruction_master/mem.s1 baseAddress {0x0000}
set_connection_parameter_value cpu.data_master/jtag_uart.avalon_jtag_slave baseAddress {0x11000}
set_connection_parameter_value cpu.data_master/cpu.debug_mem_slave baseAddress {0x10000}
set_connection_parameter_value cpu.instruction_master/cpu.debug_mem_slave baseAddress {0x10000}
set_connection_parameter_value cpu.irq/jtag_uart.irq irqNumber {0}

add_interface clk clock sink
set_interface_property clk EXPORT_OF clk.clk_in
add_interface reset reset sink
set_interface_property reset EXPORT_OF clk.clk_in_reset

save_system {nios_min.qsys}
