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
a plain `git pull` (or `git submodule update --remote`) brings in template
updates without touching your project:

```bash
cd my_project
git submodule add https://github.com/Pcsf/makefile_project_template

# One-line root Makefile that delegates to the template:
echo 'include makefile_project_template/Makefile' > Makefile

# Project configuration lives in YOUR repo, next to the root Makefile:
cp makefile_project_template/project.mk .
$EDITOR project.mk

make
```

The template detects that it is included from a parent directory and resolves
its own `make/` and `scripts/` paths accordingly; its internal tree
(`example/`, `make/`, …) is automatically excluded from source scanning.
`project.mk`, the generated `Makefile.mk` fragments, and the `.compile_order`
files all live in the consuming project — the submodule stays pristine.

Updating the template later:

```bash
git -C makefile_project_template pull origin HEAD
git add makefile_project_template
git commit -m "Update makefile template"
```

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
│   └── scan_project.bat   ← Source-tree scanner (native Windows cmd)
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
| `make fit` | `quartus` | Fitter (place & route) |
| `make asm` | `quartus` | Assembler — generate .sof |
| `make sta` | `quartus` | Static timing analysis (full flow) |
| `make program` | `vivado`, `quartus` | Program connected device |

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

# Quartus
QUARTUS_PART   := EP4CE6E22C8
QUARTUS_FAMILY := "Cyclone IV E"
QUARTUS_TOP    := top
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
