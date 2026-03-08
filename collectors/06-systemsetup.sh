# LABEL: System setup
# REQUIRES_SUDO: true

collect_systemsetup() {
    local outdir="$1"
    run_collect "systemsetup" "$outdir/systemsetup.txt" _col_systemsetup
}

_col_systemsetup() {
    echo "--- Date & Time ---"
    systemsetup -getdate 2>/dev/null || true
    systemsetup -gettime 2>/dev/null || true
    systemsetup -gettimezone 2>/dev/null || true
    systemsetup -getusingnetworktime 2>/dev/null || true
    systemsetup -getnetworktimeserver 2>/dev/null || true
    echo ""
    echo "--- Sleep ---"
    systemsetup -getsleep 2>/dev/null || true
    systemsetup -getcomputersleep 2>/dev/null || true
    systemsetup -getdisplaysleep 2>/dev/null || true
    systemsetup -getharddisksleep 2>/dev/null || true
    systemsetup -getwakeonnetworkaccess 2>/dev/null || true
    echo ""
    echo "--- Startup & Remote ---"
    systemsetup -getremotelogin 2>/dev/null || true
    systemsetup -getremoteappleevents 2>/dev/null || true
    systemsetup -getcomputername 2>/dev/null || true
    systemsetup -getstartupdisk 2>/dev/null || true
    systemsetup -getrestartfreeze 2>/dev/null || true
    systemsetup -getallowpowerbuttontosleepcomputer 2>/dev/null || true
    systemsetup -getwaitforstartupafterpowerfailure 2>/dev/null || true
}
