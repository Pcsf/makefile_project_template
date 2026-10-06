# ==============================================================================
# vivado_ipsim.tcl — simulation models of the project's IP, for xsim
#
#   vivado -mode batch -source vivado_ipsim.tcl \
#          -tclargs -params <params.tcl> -outdir <dir> -manifest <file>
#
# Creates every VIVADO_IP instance in an in-memory project, generates its
# simulation products under <dir>, and writes <file>: one line per file the
# models need, in compile order,
#
#   <library> <kind> <path>        kind: vhdl | vhdl2008 | verilog | sv | data
#
# Each core's own sources are listed in their own libraries, so xsim compiles
# them from source rather than relying on a precompiled library of the same
# name. 'data' files (memory initialisation, coefficients) are read by the
# models at run time and belong in the simulation's working directory.
#
# Like the build engine, this holds no project data: everything comes from the
# parameter file.
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir vivado_lib.tcl]

set params_file ""
set outdir      ""
set manifest    ""
for {set i 0} {$i < [llength $argv]} {incr i} {
    switch -exact -- [lindex $argv $i] {
        -params   { incr i; set params_file [lindex $argv $i] }
        -outdir   { incr i; set outdir      [lindex $argv $i] }
        -manifest { incr i; set manifest    [lindex $argv $i] }
        default   { vmk_die "unknown argument '[lindex $argv $i]'" }
    }
}
foreach {name value} [list -params $params_file -outdir $outdir -manifest $manifest] {
    if {$value eq ""} { vmk_die "missing $name" }
}

array set ::p {}
source $params_file
if {![phas ip]} { vmk_die "VIVADO_IP is empty — there is no IP to simulate" }

# The IP is generated where this run says, not in the build's output directory,
# so a simulation never disturbs the products an implementation run made.
set ::p(outdir) $outdir
file mkdir $outdir

vmk_board_repo
vmk_step "create in-memory project" [list create_project -in_memory -part [preq part]]
vmk_board_part
set_property target_language [pget target_language VHDL] [current_project]
set_property default_lib work [current_project]

vmk_create_ips 0

set out [open $manifest w]
foreach name [pget ip] {
    set files [get_files -all -compile_order sources -used_in simulation \
                   -of_objects [get_files $name.xci]]
    foreach f $files {
        set fo   [get_files -all $f]
        set type [get_property FILE_TYPE $fo]
        switch -glob -- $type {
            "VHDL 2008"     { set kind vhdl2008 }
            "VHDL*"         { set kind vhdl }
            "SystemVerilog" { set kind sv }
            "Verilog"       { set kind verilog }
            "Verilog Header" { continue }
            default         { set kind data }
        }
        set lib [get_property LIBRARY $fo]
        if {$lib eq "" || $lib eq "xil_defaultlib"} { set lib work }
        puts $out "$lib $kind [file normalize $f]"
    }
}
close $out
vmk_say "IP simulation manifest: $manifest"
exit 0
