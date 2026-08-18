#!/usr/bin/env bash
# Wrapper for qsys-script.
#
# Three reasons it is a script rather than a make recipe. qsys-script's
# save_system writes relative to the working directory, so it has to run from
# somewhere chosen while still being named by an absolute path. --search-path
# needs a trailing '$' to keep the standard IP library, which cannot be written
# reliably in a recipe built by $(eval). And qsys-script CONTINUES PAST ERRORS
# and saves anyway, so a run that could not resolve a component writes a system
# missing exactly those connections and reports failure only in its exit code —
# building from that file afterwards produces warnings that point at the design
# rather than at the generation. It therefore builds in a temporary directory
# and only replaces the real file once the run has succeeded.
#
# Usage: qsys_script.sh <shell> <script.tcl> <outdir> [search_dirs...]
set -euo pipefail

shell=$1; script=$2; outdir=$3; shift 3

script=$(cd "$(dirname "$script")" && pwd)/$(basename "$script")
outdir=$(cd "$outdir" && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

args=()
if [ "$#" -gt 0 ]; then
    joined=$(IFS=,; echo "$*")
    args+=("--search-path=${joined},\$")
fi

( cd "$work" && "$shell" qsys-script --script="$script" "${args[@]}" )

shopt -s nullglob
produced=("$work"/*.qsys)
if [ "${#produced[@]}" -eq 0 ]; then
    echo "qsys_script.sh: $script produced no .qsys — does it call save_system?" >&2
    exit 1
fi
mv "${produced[@]}" "$outdir/"
