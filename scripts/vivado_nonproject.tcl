# ==============================================================================
# vivado_nonproject.tcl — in-memory (Non-Project Mode) build engine
#
#   vivado -mode batch -source vivado_nonproject.tcl \
#          -tclargs -params <params.tcl> -stage <synth|impl|bitstream|xsa>
#
# No .xpr is ever written. The design is read, elaborated, implemented and
# exported inside one Vivado session, which is also why the whole chain runs in
# a single invocation: an in-memory design does not survive the process.
#
# Stages are cumulative — 'xsa' runs synthesis, implementation, the bitstream
# and the hardware export. Each stage leaves a checkpoint behind, so a failed
# run can be opened and inspected without rebuilding:
#
#   <outdir>/post_synth.dcp   <outdir>/post_place.dcp   <outdir>/post_route.dcp
#
# This script holds no project-specific data. Everything comes from the
# parameter file; see vivado_lib.tcl for the full key contract.
#
# Vivado writes an in-memory project's output products (.gen/, .srcs/, .Xil/)
# into the CURRENT WORKING DIRECTORY, so the caller is expected to run this
# with the build directory as cwd. The makefile does exactly that; running it
# by hand from a source tree will litter that tree instead.
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir vivado_lib.tcl]

# ── Arguments ─────────────────────────────────────────────────────────────────

set params_file ""
set stage       "bitstream"

for {set i 0} {$i < [llength $argv]} {incr i} {
    switch -exact -- [lindex $argv $i] {
        -params { incr i; set params_file [lindex $argv $i] }
        -stage  { incr i; set stage       [lindex $argv $i] }
        default {
            puts "ERROR: unknown argument '[lindex $argv $i]'"
            puts "usage: -params <file> -stage <synth|impl|bitstream|xsa>"
            exit 1
        }
    }
}

if {$params_file eq ""}            { vmk_die "no -params file given" }
if {![file exists $params_file]}   { vmk_die "parameter file not found: $params_file" }
if {[lsearch -exact {synth impl bitstream xsa} $stage] < 0} {
    vmk_die "unknown stage '$stage' (expected synth, impl, bitstream or xsa)"
}

array set ::p {}
source $params_file

set top    [preq top]
set part   [preq part]
set outdir [preq outdir]
file mkdir $outdir

# Cumulative stage predicates.
set do_impl [expr {$stage in {impl bitstream xsa}}]
set do_bit  [expr {$stage in {bitstream xsa}}]
set do_xsa  [expr {$stage eq "xsa"}]

vmk_say "=============================================================="
vmk_say " Non-Project (in-memory) build"
vmk_say "   part   : $part"
vmk_say "   top    : $top"
vmk_say "   stage  : $stage"
vmk_say "   outdir : $outdir"
vmk_say "=============================================================="

if {[phas max_threads]} { set_param general.maxThreads [pget max_threads] }

# ── 1. In-memory project ──────────────────────────────────────────────────────

vmk_board_repo
vmk_step "create in-memory project" [list create_project -in_memory -part $part]
vmk_board_part
set_property target_language [pget target_language VHDL] [current_project]
set_property default_lib work [current_project]

# ── 2. Design input ───────────────────────────────────────────────────────────
# Order matters: IP and the block design come first so the wrapper the BD
# generates is available to the RTL that instantiates it.

vmk_create_ips

set bd_wrapper [vmk_build_bd]
if {$bd_wrapper ne ""} {
    vmk_say "block design wrapper: $bd_wrapper"
    if {[string match -nocase "*.vhd*" $bd_wrapper]} {
        vmk_step "read BD wrapper" [list read_vhdl $bd_wrapper]
    } else {
        vmk_step "read BD wrapper" [list read_verilog $bd_wrapper]
    }
}

vmk_read_sources
vmk_associate_elfs
vmk_read_xdc

# ── 3. Synthesis ──────────────────────────────────────────────────────────────

set synth_args [list -top $top -part $part]
foreach g [pget generics] { lappend synth_args -generic $g }
if {[phas synth_directive]} { lappend synth_args -directive [pget synth_directive] }

vmk_step "synthesis" [concat synth_design $synth_args]
vmk_step "write post_synth.dcp" [list write_checkpoint -force [file join $outdir post_synth.dcp]]

if {[pget reports 1]} {
    report_utilization      -file [file join $outdir post_synth_utilization.rpt]
    report_timing_summary   -file [file join $outdir post_synth_timing_summary.rpt]
}

if {!$do_impl} {
    vmk_say "stage 'synth' complete — checkpoint at $outdir/post_synth.dcp"
    exit 0
}

# ── 4. Implementation ─────────────────────────────────────────────────────────

vmk_step "logic optimisation" \
    [list opt_design -directive [pget opt_directive Default]]

vmk_step "placement" \
    [list place_design -directive [pget place_directive Default]]

vmk_step "write post_place.dcp" [list write_checkpoint -force [file join $outdir post_place.dcp]]

if {[pget reports 1]} {
    report_timing_summary -file [file join $outdir post_place_timing_summary.rpt]
}

# Physical optimisation. Non-Project Mode can query slack from the in-memory
# design, so it can be spent only when it would buy something — the point of
# phys_opt_on_wns. Left off by default: on a design that already meets timing
# it is pure build time.
set phys_dir [pget phys_opt_directive]
if {$phys_dir ne ""} {
    set run_phys 1
    if {[pget phys_opt_on_wns 0]} {
        set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
        vmk_say "post-placement WNS = $wns ns"
        set run_phys [expr {$wns < 0.0}]
        if {!$run_phys} { vmk_say "timing met — skipping physical optimisation" }
    }
    if {$run_phys} {
        vmk_step "physical optimisation ($phys_dir)" \
            [list phys_opt_design -directive $phys_dir]
        write_checkpoint -force [file join $outdir post_place_physopt.dcp]
    }
}

vmk_step "routing" \
    [list route_design -directive [pget route_directive Default]]

vmk_step "write post_route.dcp" [list write_checkpoint -force [file join $outdir post_route.dcp]]

# ── 5. Post-route verification ────────────────────────────────────────────────

if {[pget reports 1]} {
    report_timing_summary    -file [file join $outdir post_route_timing_summary.rpt]
    report_timing -sort_by group -max_paths 100 -path_type summary \
                             -file [file join $outdir post_route_timing.rpt]
    report_utilization       -file [file join $outdir post_route_utilization.rpt]
    report_utilization -hierarchical \
                             -file [file join $outdir post_route_utilization_hier.rpt]
    report_clock_utilization -file [file join $outdir clock_utilization.rpt]
    report_power             -file [file join $outdir post_route_power.rpt]
    report_drc               -file [file join $outdir post_route_drc.rpt]
    report_methodology       -file [file join $outdir post_route_methodology.rpt]
}

# Timing and DRC are reported loudly but do not fail the build: a design that
# misses timing is still worth having on the bench, and deciding otherwise is
# the project's call, not the framework's.
# SLACK on a single worst path is the property that actually exists here. TNS
# is a property of a run object, which Non-Project Mode has none of — asking a
# timing_path for it fails with "[Common 17-54] The object 'timing_path' does
# not have a property 'TNS'". The totals live in post_route_timing_summary.rpt.
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
vmk_say "final timing: setup WNS = $wns ns, hold WHS = $whs ns"
if {$wns < 0.0 || $whs < 0.0} {
    puts "CRITICAL WARNING: \[FLOW\] routed design does not meet timing (WNS = $wns ns, WHS = $whs ns)"
    puts "                  see [file join $outdir post_route_timing_summary.rpt]"
}

set drc_bad [get_drc_violations -quiet \
    -filter {SEVERITY == "Critical Warning" || SEVERITY == "Error"}]
if {[llength $drc_bad] > 0} {
    puts "CRITICAL WARNING: \[FLOW\] [llength $drc_bad] DRC error/critical-warning violations"
}

if {!$do_bit} {
    vmk_say "stage 'impl' complete — checkpoint at $outdir/post_route.dcp"
    exit 0
}

# ── 6. Bitstream ──────────────────────────────────────────────────────────────

vmk_step "write bitstream" [list write_bitstream -force [file join $outdir $top.bit]]
vmk_say "bitstream: [file join $outdir $top.bit]"

if {!$do_xsa} { exit 0 }

# ── 7. Hardware platform export ───────────────────────────────────────────────
# -fixed marks the platform non-reconfigurable; -include_bit embeds the
# bitstream so Vitis can program the PL from the platform alone.

# write_hw_platform will NOT export from the in-memory routed design. With no
# implementation run to inspect, Vivado computes the platform state as
# 'pre_synth' and refuses:
#   ERROR [Common 17-69] Platform state 'pre_synth' is only supported for
#   synthesized, implemented, checkpoint or non-DFX elaborated designs
# and there is nothing to override — PLATFORM.STATE is not a property that
# exists (probed on 2021.2; the project carries PLATFORM.BOARD_ID and the
# DESIGN_INTENT set, no state).
#
# Reopening the routed checkpoint puts the design into the 'checkpoint' state
# that message names, and the export then succeeds. The block design is still
# reachable because only the DESIGN is replaced — the in-memory project, which
# is what holds the .bd, is untouched.
#
# Verified on 2021.2 by unzipping the result: the archive carries the .hwh
# handoff, ps7_init.{c,h,tcl} and the bitstream — everything Vitis needs to
# build a bare-metal platform and an FSBL.
vmk_step "reopen routed checkpoint for export" \
    [list open_checkpoint [file join $outdir post_route.dcp]]
vmk_step "export hardware platform" \
    [list write_hw_platform -fixed -include_bit -force [file join $outdir $top.xsa]]
vmk_say "hardware platform: [file join $outdir $top.xsa]"

exit 0
