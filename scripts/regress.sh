#!/usr/bin/env bash
# Regression runner for the cca_top verification environment (Verilator).
#
#   scripts/regress.sh smoke [seed]      seconds: golden self-test, cca_top_tb,
#                                        directed suite, 30 random frames
#   scripts/regress.sh full  [seed]      minutes: smoke + wide (label capacity)
#                                        + 5 random seeds x 300 frames
#                                        + 1920x1080 frames + checker self-tests
#   scripts/regress.sh selftest          every checker self-test only
#
# The seed defaults to the current time and is always printed. Reproduce one
# random run with:  ./simulate cca_random_tb +seed=<seed> +n=300
# Exit status is nonzero if any suite has an unexpected result (FAIL/XPASS).
# Logs: sim/build/regress_*.log

set -uo pipefail
cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"

MODE="${1:-smoke}"
SEED="${2:-$(date +%s)}"
LOGDIR=sim/build
mkdir -p "$LOGDIR/vectors"
STATUS=0
SUMMARY=()

record() {   # name rc log
    local res="PASS"
    [ "$2" -ne 0 ] && res="FAIL" && STATUS=1
    local counts
    counts=$(grep -E "^  (PASS|FAIL|XFAIL|XPASS|INFO) " "$3" 2>/dev/null | awk '{printf "%s=%s ", $1, $2}')
    SUMMARY+=("$(printf '%-34s %s  %s' "$1" "$res" "$counts")")
}

run_sim() {  # name  ./simulate args...
    local name=$1; shift
    local log="$LOGDIR/regress_$name.log"
    ./simulate "$@" > "$log" 2>&1
    record "$name" $? "$log"
}

run_random_seed() {  # seed n   (reuses the built random binary)
    local s=$1 n=$2 vec="$LOGDIR/vectors/cca_random_$1.txt" log="$LOGDIR/regress_random_seed$1.log"
    python3 scripts/golden/cca_golden.py random --seed "$s" --n "$n" --out "$vec" > /dev/null
    (cd "$LOGDIR" && ./sim_cca_random_tb +seed="$s" +vectors="vectors/cca_random_$s.txt") > "$log" 2>&1
    record "random seed=$s n=$n" $? "$log"
}

# selftest name -> message the injected fault must produce
SELFTESTS=(
    "data|MISMATCH"
    "stim|header.count"
    "bram_oob|outside active slot"
    "hdr_order|after the header was written"
    "irq_width|CHECK irq_width"
    "fifo|CHECK fifo_empty"
    "timing|CHECK timing"
    "label_count|CHECK label_count"
    "ps_empty|CHECK ps_empty"
)

run_selftests() {
    [ -x "$LOGDIR/sim_cca_directed_tb" ] || ./simulate cca_directed_tb > "$LOGDIR/regress_build_directed.log" 2>&1
    for entry in "${SELFTESTS[@]}"; do
        local name="${entry%%|*}" marker="${entry#*|}" log="$LOGDIR/regress_selftest_${entry%%|*}.log"
        (cd "$LOGDIR" && ./sim_cca_directed_tb +selftest="$name") > "$log" 2>&1
        local rc=$?
        # The injected fault must make the run fail AND show the right checker
        if [ "$rc" -ne 0 ] && grep -q "$marker" "$log"; then
            SUMMARY+=("$(printf '%-34s PASS  (checker caught the injected fault)' "selftest $name")")
        else
            SUMMARY+=("$(printf '%-34s FAIL  (exit %s, marker \"%s\" %s)' "selftest $name" "$rc" "$marker" \
                        "$(grep -q "$marker" "$log" && echo found || echo missing)")")
            STATUS=1
        fi
    done
}

echo "regress: mode=$MODE seed=$SEED"
python3 scripts/golden/cca_golden.py selftest > "$LOGDIR/regress_golden.log" 2>&1
record "golden model self-test" $? "$LOGDIR/regress_golden.log"

case "$MODE" in
    smoke)
        run_sim "cca_top_tb (pattern_gen smoke)" cca_top_tb
        run_sim "directed (64x48)" cca_directed_tb
        run_sim "random seed=$SEED n=30" cca_random_tb +seed="$SEED" +n=30
        ;;
    full)
        run_sim "cca_top_tb (pattern_gen smoke)" cca_top_tb
        run_sim "directed (64x48)" cca_directed_tb
        run_sim "wide label capacity (256x64)" cca_wide_tb
        run_sim "random seed=$SEED n=300" cca_random_tb +seed="$SEED" +n=300
        for i in 1 2 3 4; do run_random_seed $((SEED + i)) 300; done
        run_sim "full HD (1920x1080)" cca_full_tb
        run_selftests
        ;;
    selftest)
        run_selftests
        ;;
    *)
        echo "usage: $0 smoke|full|selftest [seed]"; exit 2 ;;
esac

echo
echo "==================== REGRESSION ($MODE, seed $SEED) ===================="
printf '%s\n' "${SUMMARY[@]}"
echo "======================================================================="
[ "$STATUS" -eq 0 ] && echo "REGRESSION PASSED" || echo "REGRESSION FAILED (see sim/build/regress_*.log)"
exit "$STATUS"
