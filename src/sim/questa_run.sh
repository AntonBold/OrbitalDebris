#!/usr/bin/env bash
# QuestaSim runner for the same testbenches ./simulate runs under Verilator.
#
#   src/sim/questa_run.sh <testbench> [+plusarg ...]
#   src/sim/questa_run.sh cca_directed_tb
#   src/sim/questa_run.sh cca_random_tb +seed=7 +n=300
#   src/sim/questa_run.sh cca_directed_tb +selftest=data
#
# Uses the same file list (scripts/filelists/<tb>.txt) and vector-generation
# hook (<tb>.pre) as ./simulate, compiles into sim/build/questa_work, and runs
# batch mode from sim/build so the default vector paths resolve. The pass/fail
# result comes from sim/build/tb_status.txt, written by cca_env_tb (vsim's exit
# code after $fatal isn't reliable across versions). Testbenches without a
# status file (cca_top_tb and the unit testbenches) report vsim's exit code.
#
# The X/Z output checker in cca_env_tb only does anything here: Verilator is
# 2-state. For the interactive waveform flow, see sim_cca_top.do.

set -uo pipefail
REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [ $# -lt 1 ]; then
    echo "usage: $0 <testbench> [+plusarg ...]"; exit 2
fi
TB="$(basename "${1%.sv}")"; shift
export SIM_ARGS="$*"
FILELIST="scripts/filelists/$TB.txt"
[ -f "$FILELIST" ] || { echo "no file list $FILELIST"; exit 2; }
[ -f "scripts/filelists/$TB.pre" ] && bash "scripts/filelists/$TB.pre"

SRCS=$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$FILELIST" | sed "s|^|$REPO_ROOT/|" | tr '\n' ' ')
mkdir -p sim/build
cd sim/build
rm -f tb_status.txt
vlib questa_work > /dev/null
vlog -sv -work questa_work $SRCS || exit 1
vsim -c -lib questa_work -voptargs=+acc "$TB" $SIM_ARGS -do "run -all; quit -f"
RC=$?

if [ -f tb_status.txt ]; then
    RESULT=$(cat tb_status.txt)
    echo "questa_run: $TB $RESULT"
    [ "$RESULT" = "PASS" ] && exit 0 || exit 1
fi
exit $RC
