# TODO — non-volatile programming

The framework can build a design and load it over JTAG. It cannot put anything
into flash. That is the gap this file scopes.

Nothing here is implemented. Everything here is a design sketch plus the
questions that have to be answered against the real tools before it can be.

> **The command syntax below is unverified.** It is written from documentation
> and recollection, not from a run. This repo's convention is that a claim
> carries the version it was proven on — none of these do yet. Treat every
> snippet as a starting point to be confirmed, not as something to paste.

## Why this matters

A build that stops at JTAG is a bench tool. Every real deployment ends with the
design in non-volatile memory: the board has to come up on its own after a power
cycle, with no cable and no host. The framework should cover that last step for
the same reason it covers the first — otherwise every project reinvents it, and
each one gets it slightly wrong.

## Scope: the matrix that has to be covered

Two axes, and they are not the same axis. Vendor decides the tools; **SoC or
not** decides what a "flash image" even is.

| | Non-SoC (fabric only) | SoC (hard processor) |
|---|---|---|
| **Xilinx / AMD** | 7-series, UltraScale(+) — flash holds a raw bitstream, loaded by the FPGA's own config engine | Zynq-7000, Zynq UltraScale+, Versal — flash holds a boot image the BootROM parses |
| **Intel / Altera** | Cyclone, Arria, MAX 10 — flash (EPCQ/EPCS, or MAX 10 internal CFM) holds a converted bitstream | Cyclone V SoC, Arria 10 SoC, Agilex — HPS boots from a preloader/U-Boot chain; the fabric image is a separate `.rbf` |

The non-SoC cases are close cousins: convert bitstream → flash image, then
program through JTAG indirect. The SoC cases are genuinely different work per
vendor, and the SoC image is not a bitstream at all — it is a boot image that
*contains* one.

**This is the trap to avoid.** `write_cfgmem` looks like the general answer and
is not. On a Zynq it is the wrong primitive: the BootROM does not load a raw
bitstream from QSPI, it loads a `BOOT.BIN` built by `bootgen`. Any design that
treats the SoC case as "non-SoC with extra steps" will be wrong.

## Proposed interface

Two vendor-neutral targets, implemented differently in `vivado.mk` and
`quartus.mk`. Consumers learn one thing.

```
make cfgmem     build the flash image from the build's own artefacts
make flash      write that image to the attached device
```

Same names on both vendors, same names SoC or not. What changes is which
variables a project sets.

### Non-SoC variables

```make
FLASH_PART      ?=          # cfgmem part / EPCQ device, e.g. mt25ql128-spi-x1_x2_x4
FLASH_INTERFACE ?= spix4    # spix1 spix2 spix4 bpix16 (Xilinx); ASx1/ASx4 (Intel)
FLASH_SIZE      ?=          # MB, Xilinx write_cfgmem -size
FLASH_OFFSET    ?= 0x0
FLASH_IMAGE     ?= $(BUILD_DIR)/$(TOP).mcs      # .mcs/.bin | .pof/.jic/.rbf
FLASH_VERIFY    ?= 1
```

### SoC variables

```make
BOOT_BIF        ?=          # bootgen descriptor (Xilinx SoC)
BOOT_ARCH       ?=          # zynq | zynqmp | versal
BOOT_FSBL       ?=          # FSBL .elf — program_flash needs it as its writer
BOOT_IMAGE      ?= $(BUILD_DIR)/BOOT.BIN
FLASH_TYPE      ?= qspi_single
```

Intel SoC needs its own set (preloader, `mkimage` u-boot script, the A2
partition scheme). Do not try to force it into the Xilinx shape.

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

Open questions: does the existing `program` target's arm_dap-skipping device
pick still apply; whether `-loadbit` offsets need to be a variable for
MultiBoot/golden-update layouts; how to enumerate valid `get_cfgmem_parts`
without hardcoding one board.

### Xilinx SoC — Zynq-7000 / Zynq UltraScale+

```sh
bootgen -arch zynq -image <x>.bif -o BOOT.BIN -w on
program_flash -f BOOT.BIN -flash_type qspi_single -fsbl <fsbl>.elf \
              -cable type xilinx_tcf
```

Open questions: `program_flash` lives in Vitis, not Vivado, so it needs the same
explicit-path treatment `XSCT` already gets; whether to expose the SD-card path
(where "flashing" is just copying `BOOT.BIN` to a FAT partition) as the same
`flash` target or a separate one; how offsets are expressed for golden/update
layouts, since `bootgen` and `program_flash` disagree about who owns them.

### Intel non-SoC — Cyclone / Arria / MAX 10

```sh
quartus_cpf -c -d <EPCQ device> -s <fpga device> <top>.sof <out>.pof   # AS
quartus_cpf -c -o device1=<...> <top>.sof <out>.jic                    # JTAG indirect
quartus_cpf -c -o bitstream_compression=on <top>.sof <out>.rbf         # raw

quartus_pgm -c <cable> -m jtag -o "p;<out>.jic"
```

Open questions: `.pof` vs `.jic` vs `.rbf` is a real fork driven by how the
board is wired (AS vs JTAG indirect vs HPS-loaded), so `FLASH_IMAGE`'s extension
probably has to drive the recipe; MAX 10 is its own case since the config flash
is on-die; a `.cof` conversion file may be needed for anything non-trivial,
which means generating one rather than passing flags.

### Intel SoC — Cyclone V SoC / Arria 10 SoC

Genuinely different: the HPS boots a preloader from a raw A2 partition, U-Boot
comes next, and the fabric gets an `.rbf` loaded by U-Boot or by the HPS at
runtime. `mkimage` builds the U-Boot script. Closer in spirit to the KV260's
SD-card flow than to anything in the Xilinx QSPI path.

Deliberately least-specified here — it needs real hardware to design against,
and there is none in reach.

## Before any of this counts as done

The repo's rule applies: a claim carries the version it was proven on.

- Every command confirmed against the actual tool version, with the error text
  recorded when it fails, the way `vivado.mk` already documents `DRC INBB-3`
  and the `pre_synth` platform state.
- **Read-back verify is not optional.** A flash write that reports success and
  produces a board that will not boot is the worst failure this framework could
  ship. `FLASH_VERIFY` defaults to on.
- A guard against writing offset 0 when a working boot image lives there. On a
  dev board that is the difference between a rebuild and a recovery exercise.
- Confirmation on at least one non-SoC and one SoC target per vendor before
  claiming the matrix is covered. Partial coverage gets documented as partial.

## Origin

Raised 2026-08-13 while converting the Vivado flow to Non-Project Mode.
Immediate driver was `tftp-field-update-basic` Phase 4, which needs the Zynq-7000
path (`bootgen` + `program_flash`, descriptors already written in its
`boot/arty/*.bif`). Parked deliberately: it does not block that project's
Phase 3, and the framework deserves the whole matrix rather than the one corner
a single project needs.
