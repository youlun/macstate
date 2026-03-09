# shellcheck shell=bash
# LABEL: Login items & launch agents
# REQUIRES_SUDO: false

collect_login_items() {
    local outdir="$1"
    run_collect "login items" "$outdir/login_items.txt" _col_login_items
}

_col_login_items() {
    echo "=== Login Items (sfltool) ==="
    sfltool dumpbtm 2>/dev/null || echo "(requires full disk access)"
    echo ""
    echo "=== User LaunchAgents ==="
    ls -la "$REAL_HOME/Library/LaunchAgents/" 2>/dev/null || echo "(none)"
    echo ""
    echo "=== System LaunchAgents ==="
    ls -la /Library/LaunchAgents/ 2>/dev/null || echo "(none)"
    echo ""
    echo "=== System LaunchDaemons ==="
    ls -la /Library/LaunchDaemons/ 2>/dev/null || echo "(none)"
}
