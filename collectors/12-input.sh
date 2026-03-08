# LABEL: Keyboard, input, accessibility, display
# REQUIRES_SUDO: false

collect_input() {
    local outdir="$1"
    run_collect "input & accessibility" "$outdir/input_accessibility.txt" _col_input
}

_col_input() {
    echo "=== Key Repeat ==="
    defaults read NSGlobalDomain KeyRepeat 2>/dev/null || true
    defaults read NSGlobalDomain InitialKeyRepeat 2>/dev/null || true
    echo ""
    echo "=== HIToolbox ==="
    defaults read com.apple.HIToolbox 2>/dev/null || true
    echo ""
    echo "=== Function Keys ==="
    defaults read NSGlobalDomain com.apple.keyboard.fnState 2>/dev/null || echo "(default)"
    echo ""
    echo "=== Press-and-hold ==="
    defaults read NSGlobalDomain ApplePressAndHoldEnabled 2>/dev/null || echo "(default)"
    echo ""
    echo "=== Auto-corrections ==="
    for key in NSAutomaticTextCompletionEnabled NSAutomaticCapitalizationEnabled \
               NSAutomaticDashSubstitutionEnabled NSAutomaticPeriodSubstitutionEnabled \
               NSAutomaticQuoteSubstitutionEnabled NSAutomaticSpellingCorrectionEnabled; do
        echo "  $key = $(defaults read NSGlobalDomain "$key" 2>/dev/null || echo '(default)')"
    done
    echo ""
    echo "=== Modifier Keys ==="
    defaults -currentHost read NSGlobalDomain com.apple.keyboard.modifiermapping 2>/dev/null || echo "(default)"
    echo ""
    echo "=== Accessibility ==="
    echo "  Dark Mode: $(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null || echo 'Light')"
    echo "  Accent Color: $(defaults read NSGlobalDomain AppleAccentColor 2>/dev/null || echo '(default)')"
    echo "  Reduce Motion: $(defaults read com.apple.universalaccess reduceMotion 2>/dev/null || echo '(default)')"
    echo "  Reduce Transparency: $(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo '(default)')"
    echo ""
    echo "=== Full universalaccess ==="
    defaults read com.apple.universalaccess 2>/dev/null || true
    echo ""
    echo "=== Display Resolution ==="
    system_profiler SPDisplaysDataType 2>/dev/null | grep -A5 Resolution || true
}
