# TODO — non-volatile programming, the three uncovered cases

The framework covers one corner of non-volatile programming: the Xilinx SoC.
`make boot-image` builds a `BOOT.BIN` with `bootgen`, `make flash-boot` writes it
into QSPI with `program_flash`, and both are documented in `make/vivado.mk` and
`README.md`. That path is implemented, proven on hardware, and out of scope here.

This file scopes what is left: **Xilinx non-SoC and Intel SoC.** Neither is
implemented. Intel non-SoC was, on 2026-08-18 — see below for what it taught,
which the two remaining cases inherit.

> **The command syntax in the sketches below is unverified.** It is written from
> documentation, not from a run. This repo's convention is that a claim carries
> the version it was proven on — none of these do yet. Treat every snippet as a
> starting point to be confirmed, not as something to paste.

## Why this matters

A build that stops at JTAG is a bench tool. Every real deployment ends with the
design in non-volatile memory: the board has to come up on its own after a power
cycle, with no cable and no host. The framework should cover that last step for
the same reason it covers the first — otherwise every project reinvents it, and
each one gets it slightly wrong.

## Scope: what is left of the matrix

Two axes, and they are not the same axis. Vendor decides the tools; **SoC or
not** decides what a "flash image" even is.

| | Non-SoC (fabric only) | SoC (hard processor) |
|---|---|---|
| **Xilinx / AMD** | **Open** — 7-series, UltraScale(+): flash holds a raw bitstream, loaded by the FPGA's own config engine | *Covered* — Zynq-7000, Zynq UltraScale+, Versal: `bootgen` + `program_flash` |
| **Intel / Altera** | *Covered* — Cyclone, Arria: `quartus_cpf` + `quartus_pgm`, proven on hardware. MAX 10's internal CFM is untried | **Open** — Cyclone V SoC, Arria 10 SoC, Agilex: HPS boots a preloader/U-Boot chain; the fabric image is a separate `.rbf` |

The two non-SoC cases are close cousins: convert bitstream → flash image, then
program through JTAG indirect. The Intel SoC case is different work again, and
its image is not a bitstream at all — it is a boot chain that loads one.

**The trap the covered corner already fell into, stated once so the remaining
work does not repeat it.** `write_cfgmem` looks like the general answer and is
not. On a Zynq it is the wrong primitive: the BootROM does not load a raw
bitstream from QSPI. That is why `flash-boot` is not `write_cfgmem` with extra
steps, and why the non-SoC targets below are new targets rather than a
generalisation of the existing ones.

## Interface

The SoC pair established the shape: **building an image and writing it are
separate targets**, because building is cheap and repeatable and writing flash is
neither. The non-SoC pair should keep that split and the same naming rhythm.

```
make cfgmem     build the flash image from the build's own artefacts
make flash      write that image to the attached device
```

Same two names on both vendors, so a consumer learns one thing. What changes is
which variables a project sets.

### Non-SoC variables

```make
FLASH_PART      ?=          # cfgmem part / EPCQ device, e.g. mt25ql128-spi-x1_x2_x4
FLASH_INTERFACE ?= spix4    # spix1 spix2 spix4 bpix16 (Xilinx); ASx1/ASx4 (Intel)
FLASH_SIZE      ?=          # MB, Xilinx write_cfgmem -size
FLASH_OFFSET    ?= 0x0
FLASH_IMAGE     ?= $(BUILD_DIR)/$(TOP).mcs      # .mcs/.bin | .pof/.jic/.rbf
FLASH_VERIFY    ?= 1
```

Intel SoC needs its own set (preloader, `mkimage` U-Boot script, the A2
partition scheme). Do not force it into either shape above.

## Lessons the covered corner already paid for

These came out of getting the SoC path working. They are not Zynq facts; they
are framework facts, and the remaining three cases inherit them.

- **A device-family fact gets no default.** `BOOT_ARCH` is required and
  `boot-image` refuses without it, because `bootgen` accepts a wrong `-arch`,
  exits 0, and emits an image the BootROM silently rejects. Any variable in the
  sketches above with the same property — one where a wrong value produces a
  plausible artefact rather than an error — must be required too, not defaulted.

- **Discover, do not name.** The FSBL that drives the flash is resolved from
  whatever the platform generated, not hardcoded to one family's directory name.
  Same rule applies to Intel's preloader and to `get_cfgmem_parts`.

- **Read-back verify is not optional.** `flash-boot` passes `-verify`
  unconditionally. A flash write that reports success and produces a board that
  will not boot is the worst failure this framework could ship. `FLASH_VERIFY`
  exists as a variable above only because the Intel tools express verification
  differently; on/off is not the choice being offered.

- **Who owns the JTAG server is a real question, not a detail.** `program_flash`
  must launch its own `hw_server`; attaching to one started by anything else
  leaves the cable enumerated but the chain unopened. Expect the same class of
  problem from `quartus_pgm` and from Vivado's hardware manager, and settle it
  deliberately rather than discovering it on a bench.

- **An offset-0 guard was considered and rejected.** A golden image legitimately
  lives at offset 0; a guard there fights the primary use case. If protection is
  wanted, it belongs in a project's own target, not the framework's.

## Per-target sketches (all unverified)

### Xilinx non-SoC — 7-series / UltraScale(+)

```tcl
write_cfgmem -format mcs -interface spix4 -size 16 \
    -loadbit "up 0x0 <top>.bit" -force <out>.mcs

open_hw_manager ; connect_hw_server ; open_hw_target
current_hw_device $dev
create_hw_cfgmem -hw_device $dev -mem_dev [lindex [get_cfgmem_parts {<part>}] 0]
set_property PROGRAM.ADDRESS_RANGE  {use_file}  [get_property PROGRAM.HW_CFGMEM $dev]
set_property PROGRAM.FILES          [list <out>.mcs] ...
set_property PROGRAM.BLANK_CHECK 0 ; PROGRAM.ERASE 1 ; PROGRAM.CFG_PROGRAM 1
set_property PROGRAM.VERIFY 1
program_hw_cfgmem [get_property PROGRAM.HW_CFGMEM $dev]
```

Closest to done of the three: it reuses the existing `program` target's Tcl
scaffolding and its device pick, which already skips `arm_dap` to find the first
programmable device.

Open questions: whether `-loadbit` offsets need to be a variable for
MultiBoot/golden-update layouts, the way the SoC path exposes a per-image
offset; how to enumerate valid `get_cfgmem_parts` without hardcoding one board.

### Intel non-SoC — Cyclone / Arria — IMPLEMENTED

`make cfgmem` builds the image and `make flash` writes it, in `make/quartus.mk`.
Proven on Quartus Prime Lite 22.1std.0.915 against a Cyclone 10 LP 10CL055 with
an EPCQ16, written over JTAG indirect and confirmed by power-cycling the board
and watching it come up on the flashed design.

```sh
quartus_cpf -o <opts> -c -d EPCQ16 -s <fpga part> <top>.sof <out>.jic   # JTAG indirect
quartus_cpf -o <opts> -c -d EPCQ16 <top>.sof <out>.pof                  # direct
quartus_cpf -o <opts> -c <top>.sof <out>.rbf                            # raw

quartus_pgm -m jtag -o "IPV;<out>.jic"    # I = indirect, P = program, V = verify
quartus_pgm -m jtag -o "BPV;<out>.pof"    # B = blank check
```

What it settled, beyond the syntax:

- **`.pof` vs `.jic` vs `.rbf` is decided by how the device is reached, not by
  preference.** A configuration device the FPGA boots from in AS mode is written
  *through* the FPGA over JTAG, which is `.jic`. `FLASH_FORMAT` selects it and
  drives which `quartus_cpf` arguments apply.
- **`FLASH_DEVICE` is required, no default.** `quartus_cpf` accepts a wrong
  configuration device, reports success, and writes an image the FPGA will not
  boot — the `BOOT_ARCH` failure mode exactly.
- **Compression is not an optimisation.** On the device this was proven against,
  one uncompressed image is 88% of the configuration memory and one compressed
  image is 25%. A golden-plus-update layout is impossible without it. The ratio
  worsens as a design fills the device, so it is a number to re-measure rather
  than a property to rely on.
- **Verify is on by default**, as `IPV`/`BPV`. `FLASH_VERIFY` exists because a
  format may not support it, not to offer turning it off.
- No `.cof` conversion file was needed; the command-line arguments covered every
  format above.

MAX 10 remains untried — its configuration flash is on-die and is a different
mechanism.

### Intel SoC — Cyclone V SoC / Arria 10 SoC

Genuinely different: the HPS boots a preloader from a raw A2 partition, U-Boot
comes next, and the fabric gets an `.rbf` loaded by U-Boot or by the HPS at
runtime. `mkimage` builds the U-Boot script.

Deliberately least-specified here — it needs real hardware to design against, and
there is none in reach.

## Before any of this counts as done

The repo's rule applies: a claim carries the version it was proven on.

- Every command confirmed against the actual tool version, with the error text
  recorded where the reader will hit it: `DRC INBB-3` next to the code that
  triggers it in `scripts/vivado_lib.tcl`, the `pre_synth` platform state in
  `scripts/vivado_nonproject.tcl`, the `hw_server` ownership failure in
  `make/vivado.mk`, and each of them again in `README.md`.
- Read-back verify on by default, per the lesson above.
- Confirmation on real hardware per case before claiming it is covered. Partial
  coverage gets documented as partial — in `README.md`'s toolchain table, not
  only here.

## Origin

Raised 2026-08-13 while converting the Vivado flow to Non-Project Mode, scoping
the whole matrix on purpose rather than the one corner a consuming project
needed at the time.

Rewritten 2026-08-17, when the Xilinx SoC corner landed and this file still
claimed the framework could not write flash at all. What that corner taught is
recorded above; what it implemented is gone from here.
