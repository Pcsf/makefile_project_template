# ==============================================================================
# vivado_project.tcl — the .xpr flows: inspection and the block-design loop
#
#   vivado -mode batch -source vivado_project.tcl \
#          -tclargs -params <params.tcl> -mode <project|bd-draft|bd-export>
#
# A project written by this script is NEVER built from. The build is the
# in-memory flow in vivado_nonproject.tcl; a .xpr exists here for two reasons
# only, both of which need the IDE:
#
#   project    a browsable copy of the design — schematic, hierarchy, IP
#              configuration dialogs. Read it, do not build it.
#
#   bd-draft   the editable block design. Seeded from the versioned BD Tcl when
#              one exists, otherwise from the bd_* bootstrap keys. Open it in
#              the IDE, wire it up, save, then export.
#
#   bd-export  writes the block design back out as Tcl. THAT file is the
#              versioned artefact the non-project build consumes — the project
#              itself is disposable.
#
# The loop is: bd-draft -> edit in the IDE -> bd-export -> commit the .tcl.
# Nothing else may be authored in the IDE, because nothing else survives.
#
# Extra parameter keys used here (see vivado_lib.tcl for the rest):
#   proj_name  required   project name
#   proj_dir   required   absolute directory to create the project in
#   bd_export  required for bd-export — absolute path of the .tcl to write
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir vivado_lib.tcl]

# ── Arguments ─────────────────────────────────────────────────────────────────

set params_file ""
set mode        "project"
set force       0

for {set i 0} {$i < [llength $argv]} {incr i} {
    switch -exact -- [lindex $argv $i] {
        -params { incr i; set params_file [lindex $argv $i] }
        -mode   { incr i; set mode        [lindex $argv $i] }
        -force  { set force 1 }
        default {
            puts "ERROR: unknown argument '[lindex $argv $i]'"
            puts "usage: -params <file> -mode <project|bd-draft|bd-export> \[-force\]"
            exit 1
        }
    }
}

if {$params_file eq ""}          { vmk_die "no -params file given" }
if {![file exists $params_file]} { vmk_die "parameter file not found: $params_file" }
if {[lsearch -exact {project bd-draft bd-export} $mode] < 0} {
    vmk_die "unknown mode '$mode' (expected project, bd-draft or bd-export)"
}

array set ::p {}
source $params_file

set proj_name [preq proj_name]
set proj_dir  [preq proj_dir]
set xpr       [file join $proj_dir $proj_name.xpr]

# ── bd-export: read an edited project back out as versioned Tcl ───────────────

if {$mode eq "bd-export"} {
    set target [preq bd_export]
    if {![file exists $xpr]} {
        vmk_die "no project at $xpr — run the bd-draft target first"
    }
    if {![phas bd_name]} { vmk_die "bd_name is not set; there is no block design to export" }
    set bd [pget bd_name]

    vmk_step "open project $xpr" [list open_project $xpr]

    set bd_file [get_files -quiet $bd.bd]
    if {$bd_file eq ""} { vmk_die "block design '$bd' not found in $xpr" }

    vmk_step "open block design" [list open_bd_design $bd_file]
    # Export what is on disk. An unsaved IDE edit is not in the project file and
    # will not appear here — save in the IDE before exporting.
    file mkdir [file dirname $target]
    vmk_step "write_bd_tcl -> $target" [list write_bd_tcl -force $target]

    vmk_say "exported block design '$bd' to:"
    vmk_say "  $target"
    vmk_say "commit that file — it is what the non-project build reads."
    exit 0
}

# ── project / bd-draft: create the project ────────────────────────────────────

# Refuse to clobber. Recreating a project silently is how IDE work gets lost:
# the old flow ran create_project -force on every build, so a block design
# drawn by hand was destroyed by the next make. Here it takes an explicit -force.
if {[file exists $xpr] && !$force} {
    vmk_die "a project already exists at $xpr.
       Open it instead, or pass FORCE=1 to recreate it from scratch.
       Recreating DISCARDS every IDE edit that has not been exported."
}

if {$force && [file exists $proj_dir]} {
    vmk_say "removing existing project at $proj_dir (-force)"
    file delete -force $proj_dir
}

file mkdir $proj_dir

vmk_board_repo
vmk_step "create project $proj_name" [list create_project $proj_name $proj_dir -part [preq part]]
vmk_board_part
set_property target_language [pget target_language VHDL] [current_project]

vmk_create_ips

set bd_wrapper [vmk_build_bd]
if {$bd_wrapper ne ""} {
    vmk_say "block design wrapper: $bd_wrapper"
    vmk_step "add BD wrapper to sources" [list add_files -norecurse $bd_wrapper]
}

# The full source set goes in even for bd-draft: seeing the RTL that
# instantiates the wrapper is most of the value of opening the IDE at all.
vmk_read_sources
vmk_read_xdc

if {[phas top]}      { set_property top [pget top] [current_fileset] }
if {[phas generics]} { set_property generic [pget generics] [current_fileset] }
update_compile_order -fileset sources_1

vmk_say "=============================================================="
if {$mode eq "bd-draft"} {
    vmk_say " Draft project ready: $xpr"
    vmk_say ""
    vmk_say " Open it in the IDE, edit the block design, and SAVE. Then export:"
    vmk_say "   from a shell : make bd-export"
    vmk_say "   from the IDE : write_bd_tcl -force [pget bd_export {<bd_export unset>}]"
    vmk_say ""
    vmk_say " The exported .tcl is the versioned artefact. This project is not."
} else {
    vmk_say " Inspection project ready: $xpr"
    vmk_say ""
    vmk_say " For reading only — the bitstream comes from the non-project flow."
    vmk_say " Anything authored here is lost unless it is exported."
}
vmk_say "=============================================================="

exit 0
