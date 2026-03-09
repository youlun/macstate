# shellcheck shell=bash
# LABEL: Installed fonts
# REQUIRES_SUDO: false

collect_fonts() {
    local outdir="$1"
    run_collect "font list" "$outdir/fonts.txt" _col_fonts
}

_col_fonts() {
    echo "=== User fonts ==="
    ls -1 "$REAL_HOME/Library/Fonts/" 2>/dev/null || echo "(none)"
    echo ""
    echo "=== System fonts (names only) ==="
    if command -v timeout &>/dev/null; then
        timeout 30 system_profiler SPFontsDataType 2>/dev/null | grep "Full Name:" | sed 's/.*Full Name: //' | sort -u || echo "(timed out or unavailable)"
    else
        system_profiler SPFontsDataType 2>/dev/null | grep "Full Name:" | sed 's/.*Full Name: //' | sort -u || echo "(unavailable)"
    fi
}
