# LABEL: System plists
# REQUIRES_SUDO: false

collect_system_plists() {
    local outdir="$1"
    mkdir -p "$outdir/system_plists" "$outdir/system_config"

    local count=0
    for plist in /Library/Preferences/*.plist; do
        [ -f "$plist" ] || continue
        local name
        name=$(basename "$plist")
        defaults read "$plist" > "$outdir/system_plists/${name}.txt" 2>/dev/null || true
        count=$((count + 1))
    done

    for plist in /Library/Preferences/SystemConfiguration/*.plist; do
        [ -f "$plist" ] || continue
        local name
        name=$(basename "$plist")
        defaults read "$plist" > "$outdir/system_config/${name}.txt" 2>/dev/null || \
            plutil -p "$plist" > "$outdir/system_config/${name}.txt" 2>/dev/null || true
        count=$((count + 1))
    done
    ok "Exported ${count} system plists"
}
