# shellcheck shell=bash
# LABEL: Sharing, Bluetooth, profiles, Time Machine
# REQUIRES_SUDO: false

collect_sharing() {
    local outdir="$1"
    run_collect "sharing" "$outdir/sharing.txt" _col_sharing
    run_collect "bluetooth" "$outdir/bluetooth.txt" _col_bluetooth
    run_collect "profiles" "$outdir/profiles.txt" _col_profiles
    run_collect "time machine" "$outdir/timemachine.txt" _col_timemachine
}

_col_sharing() {
    echo "=== Remote Login ===" ; systemsetup -getremotelogin 2>/dev/null || true
    echo "" ; echo "=== Screen Sharing ==="
    launchctl print system/com.apple.screensharing 2>/dev/null | head -10 || echo "(n/a)"
    echo "" ; echo "=== File Sharing ==="
    launchctl print system/com.apple.smbd 2>/dev/null | head -10 || echo "(n/a)"
    echo "" ; echo "=== AirDrop ==="
    defaults read com.apple.sharingd DiscoverableMode 2>/dev/null || echo "(default)"
}

_col_bluetooth() {
    defaults read /Library/Preferences/com.apple.Bluetooth 2>/dev/null || true
    echo "" ; echo "=== System Profiler ==="
    system_profiler SPBluetoothDataType 2>/dev/null || true
}

_col_profiles() {
    profiles list 2>/dev/null || profiles -L 2>/dev/null || echo "(none)"
}

_col_timemachine() {
    tmutil destinationinfo 2>/dev/null || echo "(not configured)"
    echo ""
    defaults read /Library/Preferences/com.apple.TimeMachine 2>/dev/null || echo "(not configured)"
}
