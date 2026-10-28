#!/usr/bin/env bash
# Usage: ./simulate <testbench> [+plusarg ...]
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
# Anything after the testbench name is passed to the simulation binary as
# plusargs (and exported as SIM_ARGS to the optional .pre hook), e.g.
#   ./simulate cca_random_tb +seed=7 +n=200
#   ./simulate cca_directed_tb +dump_test=12 +dump_scope=decision
#
# Assumes the testbench module name matches the filename. Override by
# exporting TOP_MODULE before calling the script if that's not the case.
#
# Waveform lands in sim/build/dump.vcd if the testbench calls $dumpfile/$dumpvars.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
FILELIST_DIR="$REPO_ROOT/scripts/filelists"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <testbench> [+plusarg ...]"
    echo "Available testbenches:"
    for f in "$FILELIST_DIR"/*.txt; do
        echo "  $(basename "${f%.txt}")"
    done
    exit 1
fi

TB_NAME="$(basename "${1%.sv}")"
shift
export SIM_ARGS="$*"
FILELIST="$FILELIST_DIR/$TB_NAME.txt"

if [ ! -f "$FILELIST" ]; then
    echo "No file list for '$TB_NAME' (expected $FILELIST)"
    exit 1
fi

# Strip comments and blank lines
SRCS="$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$FILELIST" | tr '\n' ' ')"

TOP_MODULE="${TOP_MODULE:-$TB_NAME}"

# Optional pre-build step (e.g. generating test vectors with the golden
# model): scripts/filelists/<testbench>.pre, run with bash from the repo root
PRE_HOOK="$FILELIST_DIR/$TB_NAME.pre"
if [ -f "$PRE_HOOK" ]; then
    (cd "$REPO_ROOT" && bash "$PRE_HOOK")
fi

make -C "$REPO_ROOT" sim TOP="$TOP_MODULE" SRCS="$SRCS" SIM_ARGS="$SIM_ARGS"
