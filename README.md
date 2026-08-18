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

**Non-volatile programming is covered for two cases.** On the Xilinx SoC,
`boot-image` and `flash-boot` build a `BOOT.BIN` with `bootgen` and write it to
QSPI with `program_flash` — the Zynq-7000 path, where the BootROM parses a boot
image rather than loading a raw bitstream. On the Intel side, `cfgmem`, `flash`
and `flash-erase` build and write a configuration-device image, the Active
Serial path, where the device holds a bitstream and no boot image exists. The
Xilinx non-SoC case (`write_cfgmem`) stays scoped in [`TODO.md`](TODO.md), along
with what the covered cases taught: the SoC case is not the non-SoC case with
extra steps, and treating it as one is the trap.

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
│   └── quartus.mk         ← Intel Quartus synthesis/fit/asm/STA rules,
│                             Platform Designer and Nios II
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

## How it works

The framework answers two questions — *what are the sources?* and *which tool
consumes them?* — and deliberately nothing else. Everything else is split three
ways, and that split is the whole architecture:

| Layer | Lives in | Contains |
|---|---|---|
| **Data** | `project.mk` | the project's facts: name, toolchain, top, part, pins, IP, flags |
| **Dispatch** | `Makefile` + `scripts/scan_project.sh` | source discovery, ordering, toolchain selection |
| **Flow** | `make/<toolchain>.mk` + `scripts/*.tcl` | the recipes and Tcl that actually run the tools |

The invariant that keeps this usable across projects: **nothing
project-specific or device-family-specific goes inside the framework.** A
project declares facts, the framework provides mechanism. The test before
editing anything here is whether the line would be wrong in somebody else's
project — a hardcoded `zynq_fsbl`, a hand-listed set of source files, a
testbench's private log format. If it would, it belongs in `project.mk`, or it
has to be discovered rather than named. `VITIS_BOOT_DIR_GLOB` and
`XSIM_PASS_PATTERN` are both there because of this rule.

### The include chain

A consuming project's root `Makefile` is one line — `include mk/Makefile` —
and control then runs through five steps in a fixed order:

```
mk/Makefile
  1. TEMPLATE_DIR  := $(dir $(lastword $(MAKEFILE_LIST)))
     └─ where the framework is, so it works as project root OR submodule.
        TEMPLATE_EXCLUDE keeps the framework's own example/ out of discovery.
  2. -include project.mk                      ← the project's data
  3. C_SRCS := CXX_SRCS := VHDL_SRCS := …      ← simply-expanded, see below
  4. include $(shell find … -name Makefile.mk) ← the discovered source lists
     └─ none found? bootstrap: 'make scan' then 'make all'
     └─ VHDL_SRCS_DIR set? rebuild VHDL_SRCS in the declared directory order
  5. include make/$(TOOLCHAIN).mk              ← defines 'all' and the real flow
     include make/common.mk                    ← scan / clean / info / help
```

Step 5 is why `make` means something different per toolchain without any
conditional logic in the build: `all` is defined by whichever toolchain module
was included. Under `ghdl` it is `simulate`; under `vivado` it is `bitstream`.

The order within step 5 is also what lets a toolchain module contribute to
`make help`. Set `TOOLCHAIN_HELP_TARGET` to a target the module defines, and
`common.mk` runs it between the core target list and the workflow notes:

```make
.PHONY: _help_mytool
TOOLCHAIN_HELP_TARGET := _help_mytool

_help_mytool:
	@echo ""
	@echo "  MyTool targets:"
	@echo "    program    Load the bitstream over JTAG"
```

Setting nothing is fine — `gcc` and `gxx` add no targets beyond `all`, so they
set no hook and `make help` shows the core list alone. The same is true before
the first `make scan`: the bootstrap path includes `common.mk` without any
toolchain module, so a brand-new project's `make help` lists the core targets
only until it has been scanned once.

### Why step 3 matters more than it looks

Each generated fragment appends to those lists:

```make
C_SRCS += $(wildcard $(_THIS_DIR)*.c)
```

Because step 3 initialised the variables with `:=`, this `+=` expands its
`$(wildcard …)` **immediately, at parse time, on every single `make`
invocation**. That one detail is the source of the framework's central
ergonomic claim, and its one real limitation:

- Adding or deleting a file in an existing directory needs **no rescan** — the
  next `make` already sees it.
- Adding a new source **directory** needs `make scan`, because no fragment
  exists there yet to be included.

`make scan` is safe to re-run: fragments are rewritten only when their content
would change, and a `.compile_order` is **never** overwritten once created, so
hand-tuned VHDL ordering survives. See
[How source discovery and VHDL ordering work](#how-source-discovery-and-vhdl-ordering-work)
for the mechanics and [VHDL compilation order](#vhdl-compilation-order) for the
three ordering layers.

### Data is generated, flow is committed

The Vivado module holds to the same split one level down. Make generates
exactly one Tcl file — `build/vivado_params.tcl`, a flat `::p(...)` array of
values — and the engine that reads it, `scripts/vivado_nonproject.tcl`, is
committed and reviewable on its own. No recipe writes a build script it later
sources, which is what makes a failed stage inspectable instead of
archaeological. The same holds for the Vitis and boot targets: the `.tcl` fed
to `xsct` is generated per invocation from declared variables, and the
declaration is authoritative — `VITIS_DEFINES` clears the workspace's existing
symbols before applying the project's, so deleting a line really does delete
the symbol rather than leaving a working build of the wrong firmware.

---

## Available make targets

| Target | Description |
|---|---|
| `make` / `make all` | Scan (first run only) then build |
| `make scan` | Re-scan tree; create/update `Makefile.mk` fragments |
| `make clean` | Remove the `build/` directory |
| `make distclean` | Remove `build/` **and** all generated `Makefile.mk` files |
| `make info` | Show discovered sources and current settings |
| `make help` | Print the core targets, then those of the selected toolchain |

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
| `make qsys` | `quartus` | Generate HDL from every Platform Designer system |
| `make nios-bsp` | `quartus` | Generate the board support package for each Nios II app |
| `make nios-apps` | `quartus` | Build every Nios II application into an `.elf` |
| `make cfgmem` | `quartus` | Build the configuration-memory image from the `.sof` |
| `make flash` | `quartus` | Write that image to the configuration device |
| `make flash-erase` | `quartus` | Erase the configuration device and blank-check it |
| `make program` | `vivado`, `quartus` | Program connected device |

Bare-metal software on the exported platform, and the non-volatile path
(Xilinx SoC). Kept as separate targets because the first is slow and rarely
changes while the last runs constantly:

| Target | Toolchain | Description |
|---|---|---|
| `make vitis-platform` | `vivado` | Create the hardware platform + BSP from the `.xsa`; overlay `VITIS_BOOT_SRC` onto the generated bootloader and rebuild it |
| `make vitis-apps` | `vivado` | Create/import/build every app in `VITIS_APPS` |
| `make vitis-run` | `vivado` | Reset, `ps7_init`, load the bitstream, download and run `VITIS_RUN_APP` |
| `make boot-image` | `vivado` | Build each `BOOT_IMAGES` entry from its `.bif` with `bootgen` |
| `make flash-boot` | `vivado` | Write each `BOOT_FLASH_IMAGES` entry into QSPI at its offset, with verification |

`vitis-platform` is deliberately **not** idempotent: an existing platform is an
error naming its own fix, because the reasons to re-run it — a changed `.xsa`,
a changed `VITIS_LIBS` — are exactly the cases where silently reusing a stale
one would be wrong.

**`BOOT_ARCH` has no default, and `boot-image` refuses without it.** `bootgen`
does not check `-arch` against the `.bif`: given the wrong family it reports
`Bootimage generated successfully`, exits 0, and writes an image carrying the
other family's boot header, which the BootROM will not load. The failure
surfaces as a board that does not come up, long after a build that passed. Set
`BOOT_ARCH := zynq | zynqmp | versal` in `project.mk`.

`flash-boot` stops a local `hw_server` before running `program_flash`, because
`program_flash` attaches to one that is already listening instead of launching
its own — and a server started by anything else (an `xsct` session, a chain
probe, an open Hardware Manager) leaves the cable enumerated but the chain
unopened, failing with `Given target do not exist`. Set
`BOOT_HW_SERVER_RESET := 0` when `BOOT_HW_URL` points at a server you run
deliberately.

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

### Excluding a vendored sub-project

A project that vendors a self-contained sub-project — one with its own
`project.mk` and its own sources — must keep it out of the scan:

```make
SCAN_EXCLUDE := vendor/demo        # paths relative to SRC_ROOT, space-separated
```

Without it the scan sweeps that sub-project's sources into *this* build. The
failure is not subtle for C (two `main`s, a link error) and is very subtle for
HDL (an entity compiled into the wrong library). `SCAN_EXCLUDE` filters the
scan, the sub-makefile discovery, and `distclean` alike, so a stale
`Makefile.mk` left inside an excluded directory is ignored rather than included.

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
SCAN_EXCLUDE :=              # dirs the scan must skip, relative to SRC_ROOT

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

# Quartus — Platform Designer and Nios II (omit when the design has neither)
QSYS_SYSTEMS       := system/my_system.qsys
NIOS_APPS          := hello
NIOS_hello_SRC_DIR := sw/hello
```

---

## Quartus — Platform Designer and Nios II

Proven on Quartus Prime Lite 22.1std.0.915, Cyclone 10 LP, in the container
described by `altera-dev-env`. A worked end-to-end example lives in
`example/nios2/`: a Nios II/e, on-chip memory and a JTAG UART, all free IP, so
it builds without an IP licence.

### The contract

A project declares its systems and its applications; the framework discovers
everything else.

```make
QSYS_SYSTEMS       := system/my_system.qsys   # one entry per .qsys
QSYS_LANG          := VERILOG                 # VERILOG | VHDL

NIOS_APPS          := hello
NIOS_hello_SRC_DIR := sw/hello
```

`make qsys` generates HDL, `make nios-bsp` the board support package, and
`make nios-apps` the `.elf`. `make synth` depends on `qsys`, so a plain `make`
does the right thing.

### Generated output never touches the source tree

Every artefact lands under `BUILD_DIR`:

```
build/qsys/<system>/<system>.qsys        staged copy
build/qsys/<system>/<system>.sopcinfo    generated
build/qsys/<system>/generated/…          generated HDL, and the .qip
build/nios/<app>/bsp/                    board support package
build/nios/<app>/app/<app>.elf           application
```

The staged copy is not tidiness. `qsys-generate` honours `--output-directory`
for HDL but writes the `.sopcinfo` **next to the `.qsys` it was handed**, so
generating in place drops a ~170 kB generated file into the source tree on
every build. Generating from a copy under `BUILD_DIR` is what keeps `git status`
clean.

Generated HDL enters the Quartus project as a single `QIP_FILE`, not as
enumerated sources. Platform Designer already emits a `.qip` listing every
generated file in the right order and rewrites it whenever the system changes;
enumerating that tree would be a hand-maintained list of files the tool owns.
It is deliberately absent from `V_SRCS`/`VHDL_SRCS` — `make scan` does not look
inside `BUILD_DIR`.

### Never generate a system into the source tree

`make qsys` generates under `BUILD_DIR` for a reason beyond tidiness: `make
scan` sweeps the source tree, and a hand-generated Platform Designer tree left
beside the `.qsys` gets swallowed whole. Every generated file then appears
twice — once enumerated by the scan, once through the `.qip` — and the two
disagree about file types.

The symptom is not "duplicate source". It is a SystemVerilog syntax error in
vendor IP:

```
Error (10839): Verilog HDL error at altera_tse_pipeline_stage.sv(127):
               '0 is a SystemVerilog feature
```

because the scan enumerates `.sv` files as `VERILOG_FILE` while the `.qip`
correctly declares them `SYSTEMVERILOG_FILE`. Delete the stray generated
directory and re-run `make scan`; or if a generated tree genuinely has to live
in the source tree, name it in `SCAN_EXCLUDE`.

### Configuration memory — `cfgmem` and `flash`

Proven on Quartus Prime Lite 22.1std.0.915, a Cyclone 10 LP 10CL055 and an
EPCQ16: written over JTAG indirect, then confirmed by power-cycling the board
and watching it come up on the flashed design.

```make
FLASH_DEVICE      := EPCQ16      # required — see below
FLASH_FORMAT      := jic         # jic | pof | rbf
FLASH_COMPRESSION := on
FLASH_VERIFY      := 1           # on by default
```

`make cfgmem` builds the image, `make flash` writes it. Two targets rather than
one because building is cheap and repeatable and writing flash is neither — the
same split the Xilinx `boot-image` / `flash-boot` pair uses.

`make flash-erase` erases the device and blank-checks it in the same pass. It
still takes an image, because the loader that reaches the configuration device
is built from it — nothing of the image is written. **In `quartus_pgm` option
strings `R` is erase and `E` is examine**, so the erase operation is `IR`, and
`IE` is rejected as illegal rather than quietly examining something.

Blank-checking in the same pass is the point of the target: an erase that
reports success and an erase that happened are different claims, and the
blank-check is what separates them. It is a pass-on-emptiness check, so validate
it against a programmed device — where it must fail — before trusting a pass.

**The format follows how the device is reached, not preference.** A
configuration device the FPGA boots from in Active Serial mode is written
*through* the FPGA over JTAG, which is what `jic` means; `pof` addresses the
configuration device directly; `rbf` is a raw bitstream for a loader that is not
Quartus.

**`FLASH_DEVICE` has no default, and `cfgmem` refuses without it.** `quartus_cpf`
accepts a wrong configuration device, reports success, and writes an image the
FPGA will not boot — the same failure mode that made `BOOT_ARCH` mandatory.

**Compression is not an optimisation.** On the device this was proven against,
one uncompressed image is 88% of the configuration memory and one compressed
image is 25%. Any design wanting two images in one device needs it. The ratio
depends on how full the device is and worsens as a design grows, so measure it
rather than assume it.

### Platform Designer copies component HDL — `QSYS_DEPS`

A system built from a project's own components generates by *copying* their HDL
into the generated tree. Editing that HDL therefore does not make the `.qip`
out of date: the `.qip` is still newer than the `.qsys`, make has nothing to do,
and the design synthesises the copy taken at the last generation.

The failure mode is the expensive one — the build succeeds, the board runs code
that is not in the repository, and every symptom points at the source you are
reading rather than at the source that was compiled.

```make
QSYS_SEARCH_PATH := ip/my_component
QSYS_DEPS        := rtl/my_component.vhd
```

`_hw.tcl` files under `QSYS_SEARCH_PATH` are picked up automatically. The HDL
they reference cannot be — a `_hw.tcl` may point anywhere — so name those
sources in `QSYS_DEPS`.

### A system built from a script — `QSYS_<system>_SCRIPT`

A `.qsys` can be authored by hand or built by a Tcl script. When a script is
the source, name it and the `.qsys` becomes a build product:

```make
QSYS_SYSTEMS            := system/my_sys.qsys
QSYS_my_sys_SCRIPT      := system/build_system.tcl
```

Without this the `.qsys` is just a file that happens to exist. Editing the
script changes nothing, the build keeps using whatever the file last contained,
and the two drift apart silently — the same failure as a stale component copy,
one level up.

**`qsys-script` continues past errors and saves anyway.** A run that cannot
resolve a component writes a system missing exactly the connections it could
not make, and signals the problem only through its exit code. Building from
that file afterwards produces warnings that point at the design rather than at
the generation that produced it. The wrapper therefore builds in a temporary
directory and only replaces the real file on success, so a failed run leaves
the previous system intact.

### Building one program in variants — `NIOSV_<app>_DEFINES`

When one program is built more than once from the same sources, differing only
in a compile-time setting:

```make
NIOSV_myapp_DEFINES := VARIANT=0 VERBOSE=1
```

The tool that generates the application has no option for preprocessor defines,
so they are handed to the generated build instead.

**`project.mk` is a prerequisite of every application**, because a setting
baked into an artefact is a build input like a source file. Without that,
editing the setting leaves the artefact up to date and the change simply does
not happen — the program keeps the previous definition and nothing reports that
anything was ignored. `PROJECT_MK` is available to any rule with the same
property.

### The tool-path trap

Sourcing the Quartus environment puts `quartus/linux64` and the simulator on
`PATH` **and nothing else**. `qsys-generate` lives under
`quartus/sopc_builder/bin` and the Nios II SDK under `nios2eds/`; neither is
added. A bare `qsys-generate` is "command not found" in a shell where
`quartus_map` works fine.

`nios2_command_shell.sh` is the vendor's answer, and it has a sharp edge:

```sh
nios2_command_shell.sh <command> [args…]   # runs the command with PATH set — correct
source nios2_command_shell.sh              # execs an interactive bash — never returns
```

Every Platform Designer and Nios II invocation in `quartus.mk` goes through the
wrapper in its command form. `NIOS2_SHELL` is derived from `QUARTUS_ROOTDIR`,
which the Quartus environment exports; override it only when the tools live
somewhere the derivation cannot reach.

### Getting the program into the FPGA image

`NIOS_MEM_INIT := <app>` bakes an application into the on-chip memory of the
FPGA image, so the board runs the moment it is configured:

```make
NIOS_MEM_INIT := hello
```

This inverts the usual order — synthesis waits for the `.elf` — and one
`make sta` from a clean tree runs qsys → BSP → application → memory init →
synthesis → fit → assembler → STA.

Needed whenever the program cannot arrive over a JTAG debug download after
configuration: no cable driver for the board's programmer, or a board expected
to run standalone.

**The memory instance must also be declared with its "initialize memory
content" parameter set.** With it clear, Platform Designer emits
`init_file = "UNUSED"`, the RAM synthesises empty, and the processor fetches
zeros. Nothing in the build complains — the `.hex` is generated, the QIP is
added to the project, and the memory simply ignores both. Check the fitter
report for the `.hex` filename against the RAM instance if a Nios II design
builds cleanly and does nothing.

### Two things the framework will not guess

**Which system an application runs on.** `NIOS_<app>_SOPCINFO` is derived only
when exactly one `QSYS_SYSTEMS` entry is declared. With several it is required,
because an application built against the wrong memory map links cleanly and
then does not run — the same class of failure as a wrong `BOOT_ARCH`.

**Whether the application fits.** A minimal system's on-chip memory is small and
the full C library is not. `NIOS_<app>_BSP_SETTINGS` passes settings straight to
`nios2-bsp`; `hal.enable_small_c_library=true` took the example's application
from 22 kB of text to 2.5 kB. Without it a `printf` does not fit in 32 kB.

### Building the example

```sh
cd example/nios2
make scan          # first invocation only — see below
make               # qsys → synthesis → fit → assembler → STA → .sof
make nios-apps     # the application
```

`make scan` first because the bootstrap path that runs on a tree with no
`Makefile.mk` files includes only the common targets, not the toolchain module —
so `make qsys` on a fresh clone reports "No rule to make target". A bare `make`
bootstraps and then builds, which is why the quick start does not mention this.

`example/nios2/system/build_system.tcl` is what produced the committed `.qsys`.
Keeping it beside the system means the design can be rebuilt or reviewed without
opening the GUI.

---

## Quartus — Nios V

Nios V sits beside Nios II rather than replacing it. Everything core-agnostic is
shared — Platform Designer generation, constraints, the VHDL standard handling,
the flash targets, the scan guards. The software half is a separate
implementation, because almost nothing about it is the same:

| Step | Nios II | Nios V |
|---|---|---|
| BSP | `nios2-bsp` | `niosv-bsp --create` |
| Application | generated makefile, `make -C` | `niosv-app` emits a `CMakeLists.txt`, built with CMake |
| Memory init | the BSP's `mem_init_generate` target | `elf2hex`, run by the framework |
| Extra flags | `--set APP_CFLAGS_USER_FLAGS` | a BSP setting — the toolchain file governs the app too |

### The contract

```make
NIOSV_APPS           := hello
NIOSV_hello_SRC_DIR  := sw/hello
NIOSV_hello_BSP_SETTINGS := hal.make.cflags_user_flags=-march=rv32ia_zicsr
NIOSV_MEM_INIT       := hello
NIOSV_MEM_INIT_HEX   := my_ram.hex
NIOSV_MEM_INIT_BASE  := 0x0
NIOSV_MEM_INIT_END   := 0x7FFF
```

`make niosv-bsp` generates the BSP, `make niosv-apps` builds each application,
and a declared `NIOSV_MEM_INIT` puts the program into the FPGA image so `make`
alone produces a `.sof` that runs. Every variable is listed with a commented
example in `project.mk`.

### Three things that are not in any installer

**A RISC-V toolchain.** No Intel installer ships one. The BSP writes
`riscv32-unknown-elf-gcc` into its own generated `toolchain.cmake` with a plain
`set()`, which shadows any CMake cache override, so a toolchain reachable under
a different name will not be used — provide that exact prefix, or set `NIOSV_CC`.
`niosv-shell` looks for Intel's RiscFree under `$ACDS_ROOT/riscfree`, and when
it is absent prints an INFO line and carries on, so the failure surfaces much
later as a missing compiler inside a generated CMake build. Proven here against
xPack `riscv-none-elf-gcc` 12.5.0-1, symlinked to that prefix; `rv32ia/ilp32` is
an exact multilib in it and newlib is present.

**CMake.** The application build is CMake, not a generated makefile.

**A licence, on some editions.** The Nios V/m IP is licensed (FlexLM feature
`6AF7_D036`) and, unlike Triple-Speed Ethernet, supports no evaluation mode.
Without a licence the design synthesises and fits, then `quartus_asm` reports
"successful, 0 errors" and writes no programming file at all. Check
`output_files/` for the `.sof` rather than trusting the exit status.

### The `zicsr` trap

binutils 2.38 moved the CSR instructions out of the base RISC-V `I` extension.
The processor IP hardcodes `-march=rv32ia` as a module software property, and
the BSP's own `crt0.S` writes `csrw mtvec,t0` against it, so under any binutils
at or past that release the BSP fails to assemble:

```
crt0.S:134: Error: unrecognized opcode `csrw mtvec,t0', extension `zicsr' required
```

The fix is a supported BSP setting, not a patched file:
`hal.make.cflags_user_flags=-march=rv32ia_zicsr`. It is emitted after the
hardcoded `-march` in the generated `add_compile_options`, and the compiler
takes the last one. `rv32ia` is a 32-register core; a 16-register one is
`rv32ea`.

### `LD_LIBRARY_PATH` has to be cleared

Quartus's bundled `libstdc++` shadows the system one once its environment has
been sourced, so CMake dies on a missing `GLIBCXX_3.4.30` before it ever reaches
the compiler. The framework clears it for the CMake and make invocations. The
rule is not "CMake needs this" — it is anything outside `quartus/linux64`.

### Memory initialisation

A Nios V BSP has no `mem_init_generate`, so the framework runs `elf2hex` itself.
The contract is the on-chip memory's `initializationFileName` in the Platform
Designer system: the memory is synthesised from a file of that name, and
`NIOSV_MEM_INIT_HEX` has to match it. Declare the memory with
`useNonDefaultInitFile` set, or the tool picks its own name and the two disagree
in silence.

None of the name, base or end gets a default. Each builds a plausible artefact
when wrong: a mismatched name synthesises an empty RAM and the processor fetches
zeros, a wrong range truncates the image, and nothing in the build complains.
Confirm it landed by looking in the fitter report's RAM Summary for the `.hex`
against the memory instance — the same check the Nios II flow needs.

### Building the example

```sh
cd example/niosv
make scan
make               # qsys → BSP → app → elf2hex → synthesis → … → .sof
```

Proven on Quartus Prime Lite 22.1std.0.915 with xPack `riscv-none-elf-gcc`
12.5.0-1 and CMake 3.22.1, against a 10CL025YU256C8G.

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

### The simulation verdict — why `make sim` reads the transcript

XSim's exit status is not a verdict, so `make sim` does not use it. Measured on
2021.2:

| Run | Transcript | `xsim -runall` exit |
|---|---|---|
| testbench passes | `Note: TEST COMPLETE` | **0** |
| testbench fails (`severity failure`) | `Failure: TEST FAILED` | **0** |
| testbench errors (`severity error`) | `Error: …`, run continues | **0** |
| tool failure (missing snapshot) | `ERROR: Please check the snapshot name …` | 1 |

A passing run and a run where every check failed are indistinguishable by exit
status. Left unchecked, `make sim` reports success on a testbench that failed —
a green build proving nothing, which is worse than a red one. GHDL has no such
problem: it propagates `severity failure` into its exit status, so `ghdl.mk`
needs none of this.

The transcript is therefore the source of truth. `make sim` tees it to
`$(XSIM_LOG)` and matches two patterns against it:

```make
XSIM_LOG          ?= $(BUILD_DIR)/xsim_$(VIVADO_SIM_TOP).log
XSIM_FAIL_PATTERN ?= ^(Error|Failure|Fatal):|^ERROR:   # any match fails the run
XSIM_PASS_PATTERN ?=                                    # must appear, or the run fails
XSIM_CHECK        ?= 1                                  # 0 skips the verdict
```

The default `XSIM_FAIL_PATTERN` is xsim's own rendering of VHDL severities, so
any testbench using `assert`/`report` is covered without adopting a convention;
the `ERROR:` alternative catches a tool-level failure, whose non-zero status the
pipe to `tee` would otherwise swallow.

`XSIM_PASS_PATTERN` is empty by default because a completion marker is a
testbench convention and the framework cannot know it. **Declare one** —
it is what catches the run that died quietly partway through, leaving no failing
assert to match:

```make
# project.mk
XSIM_PASS_PATTERN := TEST COMPLETE
```

`XSIM_CHECK=0` is for a run that is *expected* to fail — a TDD red phase, which
asserts the inverse against the same transcript:

```make
red:
	@$(MAKE) sim XSIM_CHECK=0 XELAB_FLAGS="$(XELAB_FLAGS) -generic_top G_RED=true"
	@grep -q "TEST FAILED" $(XSIM_LOG) || { echo "stub did not fail"; exit 1; }
```

Pass it on the command line, not in `project.mk`: a project that sets it
permanently has switched the check off.

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
VIVADO_IP_ps7_0_PRESET := vivado/board_files/<board>/<rev>/preset.xml
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

Apache License 2.0 — see [LICENSE](LICENSE). The patent grant is deliberate:
this framework drives builds that end up in shipped hardware.
