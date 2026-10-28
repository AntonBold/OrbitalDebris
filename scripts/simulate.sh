#!/usr/bin/env bash
# Usage: ./simulate <testbench>
#
# <testbench> is the testbench name, e.g. any of:
#   ./simulate cca_top_tb
#   ./simulate cca_top_tb.sv
#   ./simulate src/tb/cca_top_tb.sv
#
# The files to compile come from scripts/filelists/<testbench>.txt: one path
# per line, relative to the repo root, with # comments allowed. To add a new
# testbench, add a file list for it there.
#
# Assumes the testbench module name matches the filename. Override by
# exporting TOP_MODULE before calling the script if that's not the case.
#
# Waveform lands in sim/build/dump.vcd if the testbench calls $dumpfile/$dumpvars.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
FILELIST_DIR="$REPO_ROOT/scripts/filelists"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <testbench>"
    echo "Available testbenches:"
    for f in "$FILELIST_DIR"/*.txt; do
        echo "  $(basename "${f%.txt}")"
    done
    exit 1
fi

TB_NAME="$(basename "${1%.sv}")"
FILELIST="$FILELIST_DIR/$TB_NAME.txt"

if [ ! -f "$FILELIST" ]; then
    echo "No file list for '$TB_NAME' (expected $FILELIST)"
    exit 1
fi

# Strip comments and blank lines
SRCS="$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$FILELIST" | tr '\n' ' ')"

TOP_MODULE="${TOP_MODULE:-$TB_NAME}"

make -C "$REPO_ROOT" sim TOP="$TOP_MODULE" SRCS="$SRCS"
