# shellcheck shell=bash
# LABEL: Installed applications
# REQUIRES_SUDO: false

collect_apps() {
    local outdir="$1"
    run_collect "installed apps" "$outdir/installed_apps.txt" _col_apps
}

_col_apps() {
    echo "=== /Applications ==="
    ls -1 /Applications/ 2>/dev/null || true
    echo ""
    echo "=== ~/Applications ==="
    ls -1 "$REAL_HOME/Applications/" 2>/dev/null || echo "(none)"
    echo ""
    echo "=== Homebrew Cellar ==="
    ls -1 /opt/homebrew/Cellar/ 2>/dev/null || echo "(homebrew not installed)"
    echo ""
    echo "=== Homebrew Caskroom ==="
    ls -1 /opt/homebrew/Caskroom/ 2>/dev/null || echo "(none)"
    echo ""
    echo "=== Mac App Store apps ==="
    mas list 2>/dev/null || echo "(mas not installed)"
}
