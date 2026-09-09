#!/usr/bin/env bash
# Usage: ./simulate <top_level_tb.sv> [dependency1.sv dependency2.sv ...]
#
# Paths should be given relative to the repo root (debris_tracking/), e.g.:
#   ./simulate sim/tb/uart_tb.sv src/hdl/uart_tx.sv src/hdl/uart_rx.sv
#
# Always builds fresh and always generates a VCD waveform in sim/build/dump.vcd

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <top_level_tb.sv> [dependency.sv ...]"
    exit 1
fi

TOP_FILE="$1"
shift
DEPS="$*"

# Assumes the testbench module name matches the filename (minus extension).
# Override by exporting TOP_MODULE before calling the script if that's not the case.
TOP_MODULE="${TOP_MODULE:-$(basename "${TOP_FILE%.*}")}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

make -C "$SCRIPT_DIR" sim TOP="$TOP_MODULE" SRCS="$TOP_FILE $DEPS"
