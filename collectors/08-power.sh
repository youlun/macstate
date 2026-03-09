# shellcheck shell=bash
# LABEL: Power management
# REQUIRES_SUDO: false

collect_power() {
    local outdir="$1"
    run_collect "pmset" "$outdir/pmset.txt" _col_pmset
}

_col_pmset() {
    echo "=== Current Settings ===" ; pmset -g 2>/dev/null || true
    echo "" ; echo "=== Custom Settings ===" ; pmset -g custom 2>/dev/null || true
    echo "" ; echo "=== Assertions ===" ; pmset -g assertions 2>/dev/null || true
    echo "" ; echo "=== Power Source ===" ; pmset -g ps 2>/dev/null || true
    echo "" ; echo "=== Schedule ===" ; pmset -g sched 2>/dev/null || true
    echo "" ; echo "=== Battery ===" ; pmset -g batt 2>/dev/null || true
}
