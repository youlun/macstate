# shellcheck shell=bash
# LABEL: Dotfile contents
# REQUIRES_SUDO: false

collect_dotfile_contents() {
    local outdir="$1"
    local df_dir="$outdir/dotfile_contents"
    mkdir -p "$df_dir"

    local dotfile_list="$SCRIPT_DIR/lib/dotfiles.txt"
    local count=0

    if [ -f "$dotfile_list" ]; then
        while IFS= read -r rel; do
            [[ -z "$rel" || "$rel" == \#* ]] && continue
            local src="$REAL_HOME/$rel"
            [ -f "$src" ] || continue
            local dest="$df_dir/$rel"
            mkdir -p "$(dirname "$dest")"
            cp "$src" "$dest" 2>/dev/null || true
            count=$((count + 1))
        done < "$dotfile_list"
    else
        warn "lib/dotfiles.txt not found — using built-in list"
        local -a dotfiles=(
            ".zshrc" ".zprofile" ".bashrc" ".bash_profile" ".gitconfig"
            ".ssh/config" ".config/chezmoi/chezmoi.toml"
            ".config/starship.toml" ".config/mise/config.toml"
            ".config/ghostty/config" ".config/git/ignore"
            ".config/homebrew/Brewfile" ".config/atuin/config.toml"
            ".config/bat/config"
            "Library/Application Support/lazygit/config.yml"
        )
        for rel in "${dotfiles[@]}"; do
            local src="$REAL_HOME/$rel"
            [ -f "$src" ] || continue
            local dest="$df_dir/$rel"
            mkdir -p "$(dirname "$dest")"
            cp "$src" "$dest" 2>/dev/null || true
            count=$((count + 1))
        done
    fi

    ok "Collected ${count} dotfile contents"
}
