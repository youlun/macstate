# shellcheck shell=bash
# LABEL: Appearance, dock, window management
# REQUIRES_SUDO: false

collect_appearance() {
    local outdir="$1"
    run_collect "appearance & Tahoe features" "$outdir/appearance.txt" _col_appearance
}

_col_appearance() {
    echo "=== Appearance ==="
    defaults read com.apple.Appearance 2>/dev/null || echo "(default)"
    echo ""
    echo "=== Wallpaper ==="
    defaults read com.apple.wallpaper 2>/dev/null || echo "(default)"
    echo ""
    echo "=== Dock ==="
    defaults read com.apple.dock 2>/dev/null | grep -i -E "style|tilesize|orientation|autohide|magnif" || echo "(see dock dump)"
    echo ""
    echo "=== Window Tiling ==="
    defaults read com.apple.WindowManager 2>/dev/null || echo "(default)"
    echo ""
    defaults read com.apple.WindowManager.TileSettings 2>/dev/null || echo "(default)"
    echo ""
    echo "=== Mission Control ==="
    echo "  mru-spaces: $(defaults read com.apple.dock mru-spaces 2>/dev/null || echo '(default)')"
    echo "  expose-group-apps: $(defaults read com.apple.dock expose-group-apps 2>/dev/null || echo '(default)')"
    echo ""
    echo "=== Focus & Do Not Disturb ==="
    defaults read com.apple.donotdisturb 2>/dev/null || echo "(default)"
    echo ""
    defaults read com.apple.focus 2>/dev/null || echo "(default)"
    echo ""
    echo "=== Notification Center ==="
    defaults read com.apple.ncprefs 2>/dev/null || echo "(default)"
    echo ""
    echo "=== Apple Intelligence ==="
    defaults read com.apple.intelligence 2>/dev/null || echo "(default)"
    echo ""
    echo "=== Siri ==="
    defaults read com.apple.Siri 2>/dev/null || echo "(default)"
    defaults read com.apple.assistant.support 2>/dev/null || echo "(default)"
    echo ""
    echo "=== Game Mode ==="
    defaults read com.apple.GameController 2>/dev/null || echo "(default)"
    echo ""
    echo "=== Passwords app ==="
    defaults read com.apple.Passwords 2>/dev/null || echo "(default)"
}
