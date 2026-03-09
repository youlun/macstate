# shellcheck shell=bash
# LABEL: System info
# REQUIRES_SUDO: false

collect_system_info() {
    local outdir="$1"
    run_collect "macOS version & hardware" "$outdir/system_info.txt" _col_system_info
}

_col_system_info() {
    sw_vers
    echo "---"
    uname -a
    echo "---"
    system_profiler SPHardwareDataType 2>/dev/null || true
}
