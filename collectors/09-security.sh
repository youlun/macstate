# shellcheck shell=bash
# LABEL: Security
# REQUIRES_SUDO: false

collect_security() {
    local outdir="$1"
    run_collect "security & firewall" "$outdir/security.txt" _col_security
}

_col_security() {
    echo "=== Firewall ==="
    /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || true
    /usr/libexec/ApplicationFirewall/socketfilterfw --getblockall 2>/dev/null || true
    /usr/libexec/ApplicationFirewall/socketfilterfw --getallowsigned 2>/dev/null || true
    /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null || true
    echo ""
    echo "=== Allowed Apps ==="
    /usr/libexec/ApplicationFirewall/socketfilterfw --listapps 2>/dev/null || true
    echo ""
    echo "=== Gatekeeper ===" ; spctl --status 2>/dev/null || true
    echo "" ; echo "=== SIP ===" ; csrutil status 2>/dev/null || true
    echo "" ; echo "=== FileVault ===" ; fdesetup status 2>/dev/null || true
    echo "" ; echo "=== Secure Boot ===" ; timeout 5 bputil -d 2>/dev/null || echo "(n/a)"
}
