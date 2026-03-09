# shellcheck shell=bash
# LABEL: Network
# REQUIRES_SUDO: false

collect_network() {
    local outdir="$1"
    mkdir -p "$outdir/network"
    run_collect "scutil" "$outdir/network/scutil.txt" _col_scutil
    run_collect "networksetup" "$outdir/network/networksetup.txt" _col_networksetup
}

_col_scutil() {
    echo "=== ComputerName ===" ; scutil --get ComputerName 2>/dev/null || echo "(not set)"
    echo "=== LocalHostName ===" ; scutil --get LocalHostName 2>/dev/null || echo "(not set)"
    echo "=== HostName ===" ; scutil --get HostName 2>/dev/null || echo "(not set)"
    echo ""
    echo "=== DNS Configuration ==="
    scutil --dns 2>/dev/null || true
    echo ""
    echo "=== Proxy Configuration ==="
    scutil --proxy 2>/dev/null || true
    echo ""
    echo "=== Network Info ==="
    scutil --nwi 2>/dev/null || true
}

_col_networksetup() {
    echo "=== Network Services ==="
    networksetup -listallnetworkservices 2>/dev/null || true
    echo ""
    echo "=== Hardware Ports ==="
    networksetup -listallhardwareports 2>/dev/null || true
    echo ""
    echo "=== Per-Service Details ==="
    networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while IFS= read -r svc; do
        echo "--- $svc ---"
        networksetup -getinfo "$svc" 2>/dev/null || true
        echo "  DNS: $(networksetup -getdnsservers "$svc" 2>/dev/null || true)"
        echo "  Web Proxy: $(networksetup -getwebproxy "$svc" 2>/dev/null || true)"
        echo ""
    done
}
