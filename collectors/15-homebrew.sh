# shellcheck shell=bash
# LABEL: Homebrew packages (detailed)
# REQUIRES_SUDO: false

collect_homebrew() {
    local outdir="$1"
    local brew_dir="$outdir/homebrew"
    mkdir -p "$brew_dir"

    if ! command -v brew &>/dev/null; then
        warn "Homebrew not installed — skipping"
        return 0
    fi

    export HOMEBREW_NO_AUTO_UPDATE=1

    run_collect "brew leaves" "$brew_dir/leaves.txt" brew leaves
    run_collect "brew list" "$brew_dir/list.txt" brew list
    run_collect "brew list --cask" "$brew_dir/casks.txt" brew list --cask
    run_collect "brew tap" "$brew_dir/taps.txt" brew tap
    run_collect "brew config" "$brew_dir/config.txt" brew config
    run_collect "brew bundle dump" "$brew_dir/Brewfile" brew bundle dump --file=-
    run_collect "brew deps --installed" "$brew_dir/deps.txt" brew deps --installed

    ok "Homebrew details collected"
}
