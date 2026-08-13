# ==============================================================================
# vivado_lib.tcl — shared procedures for the Vivado flows
#
# Sourced by vivado_nonproject.tcl (the in-memory build engine) and by
# vivado_project.tcl (the .xpr flows: inspection, BD draft, BD export). It
# contains no project-specific data of any kind: everything comes from the
# generated parameter file, which is read into the global array ::p.
#
# Parameter file contract — every key is optional unless marked required:
#
#   part              required   FPGA part, e.g. xc7z020clg400-1
#   top               required   synthesis top-level unit
#   outdir            required   absolute output directory
#   board_repo                   absolute path to a vendored board_files tree
#   board_part                   board part VLNV
#   target_language              VHDL | Verilog                (default VHDL)
#   vhdl / verilog / sv          source lists, in compile order
#   vhdl93                       subset of vhdl to read as VHDL-93 (not 2008)
#   xdc                          constraint files
#   generics                     list of NAME=VALUE for synth_design -generic
#   ip                           create_ip instance names
#   ip,<name>,vlnv               VLNV for that instance
#   ip,<name>,config             flat {CONFIG.X val CONFIG.Y val} list
#   bd_name                      block design name
#   bd_tcl                       versioned write_bd_tcl output — when present
#                                it is the source of truth and every bd_* key
#                                below is ignored
#   bd_cells                     bootstrap: cell names
#   bd,<cell>,vlnv               bootstrap: cell VLNV
#   bd,<cell>,config             bootstrap: flat CONFIG list
#   bd_ext_intf / bd_ext_pins    bootstrap: pins to expose
#   bd_nets                      bootstrap: {a b} pin pairs, flat
#   bd_intf_freq                 bootstrap: {port hz} pairs, flat
#   elf                          ELF binaries to embed in block RAM
#   elf,<file>,ref               cell reference the ELF is scoped to
#   opt_directive / place_directive / route_directive / phys_opt_directive
#   phys_opt_on_wns              1 = run phys_opt only when WNS < 0
#   reports                      1 = write the report set (default 1)
#   max_threads                  set_param general.maxThreads
# ==============================================================================

# ── Parameter access ──────────────────────────────────────────────────────────

proc pget {key {default {}}} {
    if {[info exists ::p($key)]} { return $::p($key) }
    return $default
}

proc phas {key} {
    return [expr {[info exists ::p($key)] && [string trim $::p($key)] ne ""}]
}

proc preq {key} {
    if {![phas $key]} { vmk_die "required parameter '$key' is missing from the parameter file" }
    return $::p($key)
}

proc vmk_say {msg} { puts "\[FLOW\] $msg" }

proc vmk_die {msg} {
    puts "ERROR: \[FLOW\] $msg"
    exit 1
}

# Vivado returns 0 from -mode batch on a Tcl error unless the script exits
# non-zero itself, so every fallible step goes through here. A build that
# reports success without producing a bitstream is worse than a loud failure.
proc vmk_step {label script} {
    vmk_say $label
    if {[catch {uplevel 1 $script} e]} {
        puts "ERROR: \[FLOW\] $label failed:"
        puts "       $e"
        exit 1
    }
}

# ── Device and board ──────────────────────────────────────────────────────────

# board.repoPaths must be set BEFORE the project is created. Setting it
# afterwards is accepted silently and finds nothing, which surfaces later as
# "[Board 49-71] The board_part definition was not found" — confirmed on
# 2021.2 while probing this flow.
proc vmk_board_repo {} {
    if {[phas board_repo]} {
        vmk_say "board repository: [pget board_repo]"
        set_param board.repoPaths [list [pget board_repo]]
    }
}

proc vmk_board_part {} {
    if {[phas board_part]} {
        vmk_step "board part: [pget board_part]" {
            set_property board_part [pget board_part] [current_project]
        }
    }
}

# ── Sources ───────────────────────────────────────────────────────────────────

# Files are read in the order the parameter file lists them, which is the order
# the makefile framework computed from .compile_order / VHDL_SRCS_DIR. Vivado
# applies the same dependency rules as any other VHDL tool, so that order is
# the contract — no update_compile_order guessing.
proc vmk_read_sources {} {
    set vhdl93 [pget vhdl93]

    foreach f [pget vhdl] {
        if {[lsearch -exact $vhdl93 $f] >= 0} {
            vmk_step "read VHDL-93  $f"   [list read_vhdl $f]
        } else {
            vmk_step "read VHDL-2008 $f"  [list read_vhdl -vhdl2008 $f]
        }
    }
    foreach f [pget verilog] { vmk_step "read Verilog $f" [list read_verilog $f] }
    foreach f [pget sv]      { vmk_step "read SystemVerilog $f" [list read_verilog -sv $f] }
}

proc vmk_read_xdc {} {
    if {![phas xdc]} {
        puts "WARNING: \[FLOW\] no constraints (.xdc) given — timing is unconstrained"
        return
    }
    foreach f [pget xdc] { vmk_step "read constraints $f" [list read_xdc $f] }
}

# ── IP (create_ip) ────────────────────────────────────────────────────────────

# create_ip needs its -dir to exist already: Vivado does not create it and
# fails with "[Common 17-69] IP directory '...' does not exist."
proc vmk_create_ips {} {
    if {![phas ip]} { return }
    set ipdir [file join [preq outdir] ip]
    file mkdir $ipdir

    foreach name [pget ip] {
        set vlnv [preq "ip,$name,vlnv"]
        vmk_step "create IP $name ($vlnv)" \
            [list create_ip -vlnv $vlnv -module_name $name -dir $ipdir]

        if {[phas "ip,$name,config"]} {
            vmk_step "configure IP $name" \
                [list set_property -dict [pget "ip,$name,config"] [get_ips $name]]
        }
        vmk_step "generate IP targets $name" \
            [list generate_target all [get_files $name.xci]]
        # Then synthesize it out of context, explicitly. Project Mode gets this
        # for free — launch_runs spawns a child run per IP. Non-Project Mode has
        # no run manager, and synth_design does NOT compile an IP from its .xci
        # on its own, so skipping this step ends the build at:
        #   ERROR [DRC INBB-3] Cell '<inst>' of type '<ip>' has undefined
        #   contents and is considered a black box.
        # which surfaces at opt_design, long after synthesis "succeeded".
        vmk_step "synthesize IP $name (out of context)" \
            [list synth_ip [get_ips $name]]
    }
}

# ── Block design ──────────────────────────────────────────────────────────────

# Two ways in, and the choice is deliberate:
#
#   bd_tcl set — replay the versioned write_bd_tcl export. This is the source of
#     truth once it exists. It can express everything IP Integrator can:
#     interface-to-interface connections, address assignment, automation,
#     hierarchies. None of which the bootstrap keys below can.
#
#   bd_tcl unset — build the design from the bd_* keys. This is a bootstrap
#     path, good for a processor-only handoff design and nothing more. Draft it,
#     open it, export it; from then on the export wins.
#
# Verified on 2021.2 (2026-08-13): every step of this runs inside an in-memory
# project — create_bd_design, cells, config, external pins, nets, validate,
# save, generate_target all, make_wrapper — and the .hwh hardware handoff that
# Vitis needs is written just as it is in a .xpr project.
proc vmk_build_bd {} {
    if {![phas bd_name]} { return "" }
    set bd [pget bd_name]

    if {[phas bd_tcl]} {
        set tcl [pget bd_tcl]
        if {![file exists $tcl]} { vmk_die "bd_tcl does not exist: $tcl" }
        # The generated script names the design through this variable, so the
        # framework's bd_name stays authoritative even if the file was exported
        # under a different name.
        set ::design_name $bd
        vmk_step "replay block design from $tcl" [list source $tcl]
    } else {
        vmk_step "create block design $bd" [list create_bd_design $bd]
        vmk_bd_from_vars
    }

    vmk_step "validate block design" {validate_bd_design}
    vmk_step "save block design"     {save_bd_design}
    # 'all' rather than 'synthesis': the hardware handoff (.hwh) is one of the
    # output products, and write_hw_platform derives the Vitis platform from it.
    # A design exported without it gives Vitis a bitstream and nothing else —
    # no address map, no ps7_init — so no bare-metal platform and no FSBL.
    vmk_step "generate block design targets" \
        [list generate_target all [get_files $bd.bd]]

    set wrapper ""
    vmk_step "generate block design wrapper" {
        set wrapper [make_wrapper -files [get_files $bd.bd] -top -force]
    }
    return $wrapper
}

# Bootstrap construction from the flat bd_* keys.
proc vmk_bd_from_vars {} {
    foreach cell [pget bd_cells] {
        set vlnv [preq "bd,$cell,vlnv"]
        vmk_step "  bd cell $cell ($vlnv)" \
            [list create_bd_cell -type ip -vlnv $vlnv $cell]
        if {[phas "bd,$cell,config"]} {
            vmk_step "  configure $cell" \
                [list set_property -dict [pget "bd,$cell,config"] [get_bd_cells $cell]]
        }
    }
    foreach intf [pget bd_ext_intf] {
        vmk_step "  expose interface $intf" \
            [list make_bd_intf_pins_external [get_bd_intf_pins $intf]]
    }
    foreach pin [pget bd_ext_pins] {
        vmk_step "  expose pin $pin" [list make_bd_pins_external [get_bd_pins $pin]]
    }
    foreach {a b} [pget bd_nets] {
        vmk_step "  connect $a -> $b" \
            [list connect_bd_net [get_bd_pins $a] [get_bd_pins $b]]
    }
    # An external interface port does not inherit the clock rate of the pin it
    # was made from, so an overridden FCLK makes validate_bd_design fail on a
    # FREQ_HZ mismatch.
    foreach {port hz} [pget bd_intf_freq] {
        vmk_step "  set $port FREQ_HZ = $hz" \
            [list set_property CONFIG.FREQ_HZ $hz [get_bd_intf_ports $port]]
    }
}

# ── ELF association (soft-core processors) ────────────────────────────────────

# Scopes compiled software to a processor cell so write_bitstream initialises
# the block RAM with it. Only meaningful for soft cores (MicroBlaze); a Zynq PS
# loads its software from DDR/QSPI instead and needs nothing here.
proc vmk_associate_elfs {} {
    if {![phas elf]} { return }
    foreach f [pget elf] {
        set ref [pget "elf,$f,ref"]
        if {$ref eq ""} { vmk_die "elf '$f' has no 'elf,$f,ref' cell reference" }
        vmk_step "add ELF $f" [list add_files $f]
        vmk_step "scope ELF $f to $ref" \
            [list set_property SCOPED_TO_REF $ref [get_files $f]]
    }
}
