# LABEL: Dotfile contents
# REQUIRES_SUDO: false

collect_dotfile_contents() {
    local outdir="$1"
    local df_dir="$outdir/dotfile_contents"
    mkdir -p "$df_dir"

    local -a dotfiles=(
        ".zshrc"
        ".zprofile"
        ".bashrc"
        ".bash_profile"
        ".gitconfig"
        ".ssh/config"
        ".config/chezmoi/chezmoi.toml"
        ".config/starship.toml"
        ".config/mise/config.toml"
        ".config/ghostty/config"
        ".config/git/ignore"
        ".config/homebrew/Brewfile"
        "Library/Application Support/lazygit/config.yml"
        ".config/atuin/config.toml"
        ".config/bat/config"
    )

    local count=0
    for rel in "${dotfiles[@]}"; do
        local src="$REAL_HOME/$rel"
        [ -f "$src" ] || continue

        # Preserve directory structure in output
        local dest="$df_dir/$rel"
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest" 2>/dev/null || true
        count=$((count + 1))
    done

    ok "Collected ${count} dotfile contents"
}
