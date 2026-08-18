#!/usr/bin/env bash
#
# preset_to_config.sh — turn a Vivado board preset into set_property arguments.
#
# Usage:
#   preset_to_config.sh <preset.xml> <ip-name>
#
#   preset_to_config.sh vivado/board_files/<board>/<rev>/preset.xml processing_system7
#
# Prints, on one line, the CONFIG pairs for that IP:
#
#   CONFIG.PCW_DDR_RAM_BASEADDR {0x00100000} CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} ...
#
# suitable for dropping straight into a Tcl:
#
#   set_property -dict [list <output>] [get_ips ps7_0]
#
# WHY THIS EXISTS
#
# Vivado's own CONFIG.PCW_IMPORT_BOARD_PRESET property does not work on an IP
# created with create_ip outside IP Integrator. Setting it to a preset path is
# accepted silently and applies nothing: probed against Vivado 2021.2 with a
# Zynq-7000 board preset, PCW_UART0_PERIPHERAL_ENABLE, PCW_ENET0_PERIPHERAL_
# ENABLE and PCW_QSPI_PERIPHERAL_ENABLE all still read 0 immediately afterwards,
# and PCW_FPGA0_PERIPHERAL_FREQMHZ still read 50. Feeding the preset's own
# parameters in explicitly is the way to get a board-correct PS without a block
# design, and it uses the board vendor's verified MIO mapping rather than a
# hand-derived one.
#
# WHY THE IP NAME ARGUMENT IS NOT OPTIONAL
#
# A board preset file carries a preset per IP -- one measured example holds
# nine <ip_preset> blocks over 884 parameters. Emitting all of them would feed
# one IP the parameters of another. Only the block whose <ip name=...> matches
# is used.
#
# Values are wrapped in braces because some are not single words: DDR part
# numbers look like "MT41J256M16 RE-125". Braces are Tcl's literal quoting, so
# they survive the trip without further escaping.

set -euo pipefail

PRESET="${1:-}"
IP_NAME="${2:-}"

if [ -z "$PRESET" ] || [ -z "$IP_NAME" ]; then
    echo "usage: $(basename "$0") <preset.xml> <ip-name>" >&2
    exit 2
fi

if [ ! -r "$PRESET" ]; then
    echo "$(basename "$0"): cannot read preset '$PRESET'" >&2
    exit 1
fi

# The XML is flat and machine-generated, one element per line, so a streaming
# match is sufficient and avoids a dependency on an XML parser. State machine:
#   in_preset  -- inside an <ip_preset> block
#   selected   -- that block's <ip> element named the IP we want
out=$(awk -v want="$IP_NAME" '
    /<ip_preset[ >]/       { in_preset = 1; selected = 0; next }
    /<\/ip_preset>/        { in_preset = 0; selected = 0; next }

    in_preset && /<ip[ >]/ {
        # <ip vendor="xilinx.com" library="ip" name="processing_system7" version="*">
        if (match($0, /name="[^"]*"/)) {
            name = substr($0, RSTART + 6, RLENGTH - 7)
            if (name == want) selected = 1
        }
        next
    }

    selected && /<user_parameter[ >]/ {
        if (match($0, /name="[^"]*"/)) {
            pname = substr($0, RSTART + 6, RLENGTH - 7)
        } else next
        if (match($0, /value="[^"]*"/)) {
            pvalue = substr($0, RSTART + 7, RLENGTH - 8)
        } else next
        printf "%s {%s} ", pname, pvalue
    }
' "$PRESET")

if [ -z "$out" ]; then
    echo "$(basename "$0"): no preset for IP '$IP_NAME' in $PRESET" >&2
    exit 1
fi

printf '%s\n' "$out"
