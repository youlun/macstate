# shellcheck shell=bash
# LABEL: Key app domains
# REQUIRES_SUDO: false

collect_defaults_apps() {
    local outdir="$1"
    local app_dir="$outdir/individual_apps"
    mkdir -p "$app_dir"

    local -a domains=(
        com.apple.finder com.apple.dock com.apple.Safari com.apple.mail
        com.apple.Terminal com.apple.systempreferences com.apple.screensaver
        com.apple.screencapture com.apple.menuextra.clock com.apple.menuextra.battery
        com.apple.AppleMultitouchTrackpad com.apple.AppleMultitouchMouse
        com.apple.driver.AppleBluetoothMultitouch.trackpad com.apple.HIToolbox
        com.apple.TextEdit com.apple.Preview com.apple.Notes com.apple.Maps
        com.apple.universalaccess com.apple.WindowManager com.apple.controlcenter
        com.apple.Spotlight com.apple.SoftwareUpdate com.apple.loginwindow
        com.apple.spaces com.apple.notificationcenterui
        com.apple.Phone com.apple.FaceTime com.apple.Appearance
        com.apple.WindowManager.TileSettings com.apple.donotdisturb
        com.apple.focus com.apple.intelligence com.apple.Passwords
        com.apple.GameController com.apple.Siri com.apple.assistant.support
        com.apple.wallpaper com.apple.ncprefs com.apple.sharingd
    )

    for d in "${domains[@]}"; do
        local safe="${d//\//_}"
        defaults read "$d" > "$app_dir/${safe}.txt" 2>/dev/null || true
    done
    ok "Exported ${#domains[@]} key domains"
}
