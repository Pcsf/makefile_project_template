# Makefile Project Template

A portable, multi-toolchain firmware/HDL project template built on GNU Make.

A helper script scans the source tree and places a `Makefile.mk` fragment in
every directory that contains source files.  Each fragment uses GNU make's
`$(wildcard …)` function so **the source list updates automatically on every
`make` invocation** — no manual editing required when files are added or
removed within an existing directory.

---

## Supported toolchains

| `TOOLCHAIN=` | Languages | Tools |
|---|---|---|
| `gcc` | C | GCC `gcc` |
| `gxx` | C, C++ | GCC `gcc` / `g++` |
| `ghdl` | VHDL | GHDL |
| `modelsim` | VHDL, Verilog, SV | ModelSim / QuestaSim |
| `vivado` | VHDL, Verilog, SV + XDC | Xilinx Vivado |
| `quartus` | VHDL, Verilog, SV | Intel/Altera Quartus Prime |

---

## Quick start

```bash
# 1. Clone (or copy) the template
git clone https://github.com/pcsf/makefile_project_template my_project
cd my_project

# 2. Edit project configuration
$EDITOR project.mk          # set PROJECT_NAME, TOOLCHAIN, compiler flags …

# 3. Add your source files anywhere under the project root, e.g.:
mkdir -p src/app src/drivers
cp ~/my_code/*.c src/app/

# 4. Build — the scan runs automatically on the first invocation
make

# Subsequent builds pick up new/removed files within existing directories
# automatically.  For a brand-new source directory, run:
make scan
```

---

## Using as a git submodule (recommended)

Instead of copying the template into each project, embed it as a submodule so
a plain `git pull` inside the submodule brings in template updates without
touching your project. The checkout path is free — a short name like `mk/`
keeps invocations tidy:

```bash
cd my_project
git submodule add https://github.com/Pcsf/makefile_project_template mk

# One-line root Makefile that delegates to the template:
echo 'include mk/Makefile' > Makefile

# Project configuration lives in YOUR repo, next to the root Makefile:
cp mk/project.mk .
$EDITOR project.mk

make
git add .gitmodules mk Makefile project.mk
git commit -m "Add make-based build via makefile_project_template submodule"
```

The template detects that it is included from a parent directory and resolves
its own `make/` and `scripts/` paths accordingly; its internal tree
(`example/`, `make/`, …) is automatically excluded from source scanning.
`project.mk`, the generated `Makefile.mk` fragments, and the `.compile_order`
files all live in the consuming project — the submodule stays pristine.

Anyone cloning the consuming project needs the submodule populated before the
first build:

```bash
git clone --recurse-submodules <project-url>
# or, in an existing clone:
git submodule update --init
```

Updating the template later:

```bash
git -C mk pull
git add mk
git commit -m "Update makefile template"
```

### Worked example: a VHDL simulation project

[cdc-lib](https://github.com/Pcsf/cdc-lib) uses this exact setup to run a
GHDL testbench. Its layout:

```
cdc-lib/
├── Makefile             ← 'include mk/Makefile' (one line)
├── project.mk           ← project configuration (see below)
├── mk/                  ← this template, as a submodule
├── src/                 ← VHDL sources
│   └── .compile_order   ← within-directory compile order (committed)
└── tb/                  ← testbench
    └── .compile_order
```

The relevant `project.mk` settings:

```makefile
PROJECT_NAME := cdc_lib
TOOLCHAIN    := ghdl

# src (package + entities) before tb (instantiates them):
VHDL_SRCS_DIR := \
    src          \
    tb

GHDL_STD := 93
GHDL_TOP := tb_cdc_lib
```

With that in place, `make` scans on the first run, analyses everything in the
declared order, elaborates `tb_cdc_lib`, and runs the simulation with a VCD
written to `build/`. The consuming repo ignores the generated fragments
(`**/Makefile.mk` in `.gitignore`) and commits the `.compile_order` files.

---

## Directory layout

```
makefile_project_template/
├── Makefile               ← Root makefile (do not edit)
├── project.mk             ← YOUR project configuration (edit this)
├── make/
│   ├── common.mk          ← Utility targets: scan, clean, help, info
│   ├── gcc.mk             ← GNU C toolchain rules
│   ├── gxx.mk             ← GNU C++ toolchain rules
│   ├── ghdl.mk            ← GHDL VHDL simulation rules
│   ├── modelsim.mk        ← ModelSim / QuestaSim rules
│   ├── vivado.mk          ← Xilinx Vivado synthesis/implementation rules
│   └── quartus.mk         ← Intel Quartus synthesis/fit/asm/STA rules
├── scripts/
│   ├── scan_project.sh    ← Source-tree scanner (Linux / macOS / WSL)
│   ├── scan_project.bat   ← Source-tree scanner (native Windows cmd)
│   ├── preset_to_config.sh ← Board preset XML → set_property CONFIG pairs
│   ├── vivado_lib.tcl     ← Shared Vivado procedures (sources, IP, BD, ELF)
│   ├── vivado_nonproject.tcl ← In-memory build engine (the build)
│   └── vivado_project.tcl ← .xpr flows: inspection + block-design round trip
├── templates/
│   └── Makefile.mk.tmpl   ← Reference copy of the generated fragment
└── example/
    ├── src/
    │   ├── main.c
    │   └── utils/
    │       ├── utils.c
    │       └── utils.h
    └── hdl/
        ├── top.vhd
        └── modules/
            └── counter.vhd
```

After `make scan`, each source directory gains a `Makefile.mk`:

```
src/
├── Makefile.mk            ← auto-generated, $(wildcard *.c) inside
├── main.c
└── utils/
    ├── Makefile.mk        ← auto-generated
    ├── utils.c
    └── utils.h
```

---

## Available make targets

| Target | Description |
|---|---|
| `make` / `make all` | Scan (first run only) then build |
| `make scan` | Re-scan tree; create/update `Makefile.mk` fragments |
| `make clean` | Remove the `build/` directory |
| `make distclean` | Remove `build/` **and** all generated `Makefile.mk` files |
| `make info` | Show discovered sources and current settings |
| `make help` | Print this target list |

Toolchain-specific targets (available when the relevant toolchain is selected):

| Target | Toolchain | Description |
|---|---|---|
| `make analyze` | `ghdl` | Parse and type-check all VHDL |
| `make elaborate` | `ghdl` | Build simulation binary |
| `make simulate` | `ghdl` | Run simulation, emit VCD |
| `make compile` | `modelsim` | Compile HDL into work library |
| `make simulate` | `modelsim` | Run simulation with vsim |
| `make synth` | `vivado`, `quartus` | Synthesis only |
| `make impl` | `vivado` | Implementation (place & route) |
| `make bitstream` | `vivado` | Full flow to bitstream |
| `make xsa` | `vivado` | Full flow, then export the hardware platform (`.xsa`) |
| `make sim` / `sim-gui` | `vivado` | XSim behavioural simulation |
| `make gui` | `vivado` | Open the newest checkpoint in the IDE (read) |
| `make project` | `vivado` | Build a browsable `.xpr` from the same sources (read) |
| `make project-gui` | `vivado` | Open that project in the IDE |
| `make bd-draft` | `vivado` | Create the editable block-design project |
| `make bd-export` | `vivado` | Write the block design back out as versioned Tcl |
| `make fit` | `quartus` | Fitter (place & route) |
| `make asm` | `quartus` | Assembler — generate .sof |
| `make sta` | `quartus` | Static timing analysis (full flow) |
| `make program` | `vivado`, `quartus` | Program connected device |

`FORCE=1` is required by `project` and `bd-draft` to overwrite an existing
project — recreating one discards every IDE edit that has not been exported.

---

## How source discovery and VHDL ordering work

### Initial scan

```
make scan
  └─ bash scripts/scan_project.sh .
       ├─ finds hdl/           → writes hdl/Makefile.mk  +  hdl/.compile_order
       ├─ finds hdl/modules/   → writes hdl/modules/Makefile.mk  +  hdl/modules/.compile_order
       ├─ finds src/           → writes src/Makefile.mk
       └─ finds src/utils/     → writes src/utils/Makefile.mk
```

Each generated `Makefile.mk` contains:

```makefile
_THIS_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

C_SRCS    += $(wildcard $(_THIS_DIR)*.c)
CXX_SRCS  += $(wildcard $(_THIS_DIR)*.cpp $(_THIS_DIR)*.cxx $(_THIS_DIR)*.cc)

# VHDL: uses .compile_order when present, wildcard otherwise
ifneq ($(wildcard $(_THIS_DIR).compile_order),)
VHDL_SRCS += $(addprefix $(_THIS_DIR),$(shell grep -v '^[[:space:]]*#' …))
else
VHDL_SRCS += $(wildcard $(_THIS_DIR)*.vhd $(_THIS_DIR)*.vhdl)
endif

V_SRCS    += $(wildcard $(_THIS_DIR)*.v   $(_THIS_DIR)*.sv)
ASM_SRCS  += $(wildcard $(_THIS_DIR)*.s   $(_THIS_DIR)*.S   $(_THIS_DIR)*.asm)
```

### Subsequent builds

The root `Makefile` initialises `C_SRCS :=` (simple-expanded) **before**
including the fragments.  Because `C_SRCS` is a simple-expanded variable, every
`+=` with `$(wildcard …)` expands **immediately** at parse time — source lists
are always current with no rescanning.

```
make
  ├─ root Makefile: C_SRCS :=, VHDL_SRCS :=, …
  ├─ include src/Makefile.mk          → C_SRCS = src/main.c
  ├─ include src/utils/Makefile.mk    → C_SRCS += src/utils/utils.c
  ├─ include hdl/modules/Makefile.mk  → VHDL_SRCS = hdl/modules/counter.vhd  (from .compile_order)
  ├─ include hdl/Makefile.mk          → VHDL_SRCS += hdl/top.vhd              (from .compile_order)
  └─ compile & link
```

Add `new_file.c` to `src/` → next `make` picks it up automatically.
Add a new directory `src/hal/` with `.c` files → run `make scan` once.

---

## VHDL compilation order

VHDL requires packages and entities to be compiled before any design unit that
references them.  Three layers handle this, from most to least automatic:

### Layer 3 — silent pre-pass (automatic)

`ghdl.mk` and `modelsim.mk` compile all VHDL files once with errors silenced
before the real pass.  Any file that succeeds pre-populates the work library so
the real pass finds all dependencies already there.  **Most designs need no
further action.**

### Layer 2 — `.compile_order` file (per directory)

`make scan` creates a `.compile_order` in each VHDL directory listing files
alphabetically as a starting point.  **Edit it once** to set the correct
within-directory order.  It is **never overwritten** by subsequent `make scan`
runs, so your edits survive.  Commit it alongside your source files.

```
hdl/modules/.compile_order
  # list counter before any entity that instantiates it
  counter.vhd
```

### Layer 1 — `VHDL_SRCS_DIR` (cross-directory ordering)

When a package in one directory is used by entities in another, set
`VHDL_SRCS_DIR` in `project.mk` to list **directories** in compilation order.
The root Makefile expands each directory through its `.compile_order` (or
wildcard) — **you declare directory order, file discovery stays automatic**.

```makefile
# project.mk
VHDL_SRCS_DIR := \
    hdl/lib         \   # packages compiled first
    hdl/rtl         \   # entities that use those packages
    hdl/top             # top-level that instantiates rtl entities
```

This replaces what the per-directory `Makefile.mk` fragments accumulated, so
**all** VHDL directories must appear in the list when this variable is set.

---

## Configuring project.mk

```makefile
PROJECT_NAME := my_project   # output binary name
BUILD_DIR    := build        # build artefact directory
TOOLCHAIN    := gcc          # see table above

# C / C++
CC       := gcc
CFLAGS   := -Wall -Wextra -O2 -g
INC_DIRS := include third_party/include

# GHDL
GHDL_STD := 08
GHDL_TOP := top

# Vivado
VIVADO_PART := xc7a35tcpg236-1
VIVADO_TOP  := top
VIVADO_XDC  := constraints/pins.xdc

# Implementation strategy — Default everywhere; escalate where timing bites.
# Explore-class directives cost real time on every build, so they are opt-in.
VIVADO_OPT_DIRECTIVE      := Default
VIVADO_PLACE_DIRECTIVE    := Default
VIVADO_ROUTE_DIRECTIVE    := Default
VIVADO_PHYS_OPT_DIRECTIVE :=          # empty = skip phys_opt entirely
VIVADO_PHYS_OPT_ON_WNS    := 0        # 1 = run it only when placement missed
VIVADO_REPORTS            := 1        # utilization, timing, power, DRC, methodology

# Quartus
QUARTUS_PART   := EP4CE6E22C8
QUARTUS_FAMILY := "Cyclone IV E"
QUARTUS_TOP    := top
```

---

## Vivado build flow — Non-Project Mode

The build is **Non-Project Mode**: sources are read, implemented and exported
inside one in-memory Vivado session and no `.xpr` is written. Everything the
build needs comes from `project.mk`, so a fresh clone reproduces the design
exactly.

The flow lives in three committed, reviewable Tcl files under `scripts/`:

| File | Role |
|---|---|
| `vivado_lib.tcl` | shared procedures — sources, IP, block design, ELF |
| `vivado_nonproject.tcl` | the in-memory build engine (`synth`→`impl`→`bitstream`→`xsa`) |
| `vivado_project.tcl` | the `.xpr` flows: inspection and the block-design round trip |

None of them contains project-specific data. Make generates exactly one file —
`build/vivado_params.tcl`, a flat parameter array — and the engine sources it.
Data is generated; flow is committed.

Each stage is cumulative and runs in a single Vivado invocation, because an
in-memory design does not outlive the process. Every stage leaves a checkpoint
in `build/nonproject/`, so a failed run can be opened and inspected without
rebuilding:

```
post_synth.dcp   post_place.dcp   post_route.dcp
```

Two things that are easy to get wrong here, both learned by hitting them:

- **IP must be synthesized explicitly.** Project Mode gets this free — the run
  manager spawns a child run per IP. Non-Project Mode has none, and
  `synth_design` will not compile an IP from its `.xci`. Skip `synth_ip` and the
  build dies at `opt_design` with `DRC INBB-3 … considered a black box`, long
  after synthesis reported success. `vivado_lib.tcl` does this for every IP.

- **Compilation order is the contract.** There is no `update_compile_order` to
  fall back on, so the order from `.compile_order` / `VHDL_SRCS_DIR` is what
  Vivado gets.

### The project is for reading

A `.xpr` is still available, but nothing is ever built from one:

```sh
make gui           # open the newest checkpoint — the usual way to inspect a build
make project       # build a browsable .xpr from the same sources
make project-gui   # open it
```

Nothing authored in the IDE survives, with exactly one sanctioned exception:
the block design round trip below.

---

## Vivado block designs

A block design is authored in the IDE and stored as **versioned Tcl**. The round
trip is:

```sh
make bd-draft      # create the editable project, seeded from what exists
                   # ... open it, wire it up, SAVE ...
make bd-export     # write_bd_tcl -> $(VIVADO_BD_TCL)
git add $(VIVADO_BD_TCL)
```

From then on `VIVADO_BD_TCL` is the source of truth: the build replays it and
every `VIVADO_BD_*` key below is ignored. Those keys are a **bootstrap** — they
seed the first draft so a processor-only handoff design works before anyone has
opened the IDE, and they stop being read the moment an export exists.

This matters because the export can express everything IP Integrator can —
interface-to-interface connections, address assignment, `apply_bd_automation`,
hierarchies — none of which the bootstrap keys can reach. The cost is that
`write_bd_tcl` output is verbose (tens of KB), re-emits every cell's full config
dict, and embeds a Vivado version check that errors on a mismatch.

### Declaring one

```make
# project.mk
VIVADO_BD           := ps_bd                       # block design name
VIVADO_BD_TCL       := vivado/bd/ps_bd.tcl         # versioned export — canonical
                                                   # once it exists

# Bootstrap only — ignored as soon as VIVADO_BD_TCL exists on disk:
VIVADO_BD_CELLS     := ps7_0                       # cells inside it
VIVADO_BD_EXT_INTF  := ps7_0/DDR ps7_0/FIXED_IO ps7_0/M_AXI_GP0
VIVADO_BD_EXT_PINS  := ps7_0/FCLK_CLK0 ps7_0/FCLK_RESET0_N
VIVADO_BD_NETS      := ps7_0/M_AXI_GP0_ACLK=ps7_0/FCLK_CLK0
VIVADO_BD_INTF_FREQ := M_AXI_GP0_0=125000000

# Cells reuse the same variables as create_ip IP:
VIVADO_IP_ps7_0_VLNV   := xilinx.com:ip:processing_system7:5.5
VIVADO_IP_ps7_0_PRESET := vivado/board_files/arty-z7-20/A.0/preset.xml
VIVADO_IP_ps7_0_CONFIG := CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ=125
```

The generated wrapper is added to `sources_1`. **Instantiate it from your own
top** rather than making it the top, so the block design stays as small as
whatever forced you to have one, and the rest of the fabric stays in RTL where
it is reviewable and diffable.

`VIVADO_BD_INTF_FREQ` is not decoration: external interface ports do not inherit
the clock rate of the pin they were made from, so overriding an FCLK makes
`validate_bd_design` fail with a `FREQ_HZ` mismatch between the port and the
interface.

### What the bootstrap keys can and cannot express

| Can | Cannot |
|---|---|
| Create cells of any VLNV | Connect interfaces between cells (`connect_bd_intf_net`) |
| Configure them (`_PRESET`, `_CONFIG`) | Assign addresses (`assign_bd_address`) |
| Expose interface pins externally | `apply_bd_automation` |
| Expose scalar pins externally | Hierarchies / nested blocks |
| Connect scalar pins | Ordering beyond this fixed sequence |
| Set external interface `FREQ_HZ` | |

This covers "a processor with its pins brought out", which is all a
hardware-platform export usually needs. **Anything richer is not a reason to
extend `make/vivado.mk` — it is a reason to draft, edit and export.** The
exported Tcl has none of these limits, which is the whole point of the round
trip.

To see exactly what make hands the flow, read `build/vivado_params.tcl`.

### Working in the IDE

```sh
make bd-draft                       # refuses to clobber; FORCE=1 to recreate
make project-gui                    # open it
```

The draft is seeded from `VIVADO_BD_TCL` when that file exists, and from the
bootstrap keys when it does not — so the loop is genuinely round-trippable:
export, edit, re-export, and the diff is just your change.

Edit, **save in the IDE**, then export. `bd-export` reads what is on disk; an
unsaved edit is not in the project file and will not appear in the output.
You can also export from the IDE's own Tcl console without leaving it:

```tcl
write_bd_tcl -force <VIVADO_BD_TCL>
```

`make bd-draft` prints that exact line, with the path filled in.

---

## Hardware platform export (XSA)

```sh
make xsa                       # -> $(VIVADO_XSA), default build/$(VIVADO_TOP).xsa
```

Runs synthesis, implementation, the bitstream and `write_hw_platform -fixed
-include_bit` in a **single** Vivado invocation — an in-memory design does not
outlive the process, so there is nothing for a second invocation to find.

The export has one non-obvious step in it. `write_hw_platform` refuses to run
against the in-memory routed design: with no implementation run to inspect,
Vivado computes the platform state as `pre_synth` and fails with

```
ERROR: [Common 17-69] Platform state 'pre_synth' is only supported for
synthesized, implemented, checkpoint or non-DFX elaborated designs
```

There is nothing to override — `PLATFORM.STATE` is not a property that exists.
The fix is to reopen the routed checkpoint, which puts the design into the
`checkpoint` state that message names. The block design survives that, because
only the *design* is replaced and the in-memory *project* still holds the `.bd`.
Verified on 2021.2: the resulting archive carries the `.hwh`, `ps7_init.*` and
the bitstream.

**An XSA is only useful to Vitis if the design contains a block design.**
`write_hw_platform` derives its `.hwh` hardware handoff from one. Export from a
pure-RTL design and you get an archive holding just a bitstream — no address
map, no `ps7_init`, nothing to build a bare-metal platform or an FSBL from. That
is the usual reason to introduce a block design at all, even a single-cell one.

Judge an export by its `sysdef.xml`, not `xsa.xml`. The latter is the
acceleration-flow manifest and can still report `PlatformState="pre_synth"` for
a perfectly good embedded platform. A complete embedded export lists:

```
HW_HANDOFF     <bd>.hwh
PS_FSBL_INIT   ps7_init.c / ps7_init.h
PS_XMD_INIT    ps7_init.tcl
BIT            <top>.bit
```

---

## Windows (native cmd.exe)

The `.bat` scanner requires PowerShell (available on Windows 7+) to write
`Makefile.mk` content without escaping issues.  Make itself should be
installed via [WinLibs](https://winlibs.com/),
[MSYS2](https://www.msys2.org/), or
[GNU Make for Windows](https://gnuwin32.sourceforge.net/packages/make.htm).

Alternatively, use [Git Bash](https://git-scm.com/downloads) or WSL and run
`scripts/scan_project.sh` directly.

---

## Adding a new toolchain

1. Create `make/<name>.mk` following the pattern of the existing toolchain
   files.
2. Define:
   - An `all:` phony target.
   - A recipe for `$(BUILD_DIR)/$(PROJECT_NAME)` (may be an alias/phony).
3. Set `TOOLCHAIN := <name>` in `project.mk`.

---

## License

MIT — see [LICENSE](LICENSE) (add your own LICENSE file).
