PROJECT_NAME := vhdl_libraries_test
BUILD_DIR    := build
TOOLCHAIN    := ghdl
SRC_ROOT     := .
SCAN_EXCLUDE := hdl/lib_a hdl/lib_b

GHDL_STD := 08
GHDL_TOP := tb_named_libraries
VSIM_TOP := tb_named_libraries

VHDL_SRCS_DIR := hdl

VHDL_LIBS := lib_a lib_b
VHDL_LIB_lib_a_SRCS := hdl/lib_a/value_pkg.vhd
VHDL_LIB_lib_b_SRCS := hdl/lib_b/doubled_pkg.vhd
VHDL_LIB_lib_b_DEPS := lib_a
