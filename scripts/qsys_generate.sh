#!/usr/bin/env bash
# Wrapper for qsys-generate.
#
# It exists for one reason: --search-path needs a trailing '$' to keep the
# standard IP library, and that '$' cannot be written reliably in a make recipe
# built by $(eval) — every escaping either resolves to the shell's process id or
# is consumed and leaves a quote open. Here it is a plain character in a script.
#
# Usage: qsys_generate.sh <shell> <qsys> <lang> <part> <outdir> [search_dirs...]
set -euo pipefail

shell=$1; qsys=$2; lang=$3; part=$4; outdir=$5; shift 5

args=()
if [ "$#" -gt 0 ]; then
    joined=$(IFS=,; echo "$*")
    args+=("--search-path=${joined},\$")
fi

exec "$shell" qsys-generate "$qsys" \
    "${args[@]}" \
    --synthesis="$lang" \
    --output-directory="$outdir" \
    --part="$part"
