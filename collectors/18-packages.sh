# shellcheck shell=bash
# LABEL: Global packages (npm, pip, gem, mise)
# REQUIRES_SUDO: false

collect_packages() {
    local outdir="$1"
    local pkg_dir="$outdir/packages"
    mkdir -p "$pkg_dir"

    if command -v npm &>/dev/null; then
        run_collect "npm global packages" "$pkg_dir/npm_global.txt" npm list -g --depth=0
    fi

    if command -v pip3 &>/dev/null; then
        run_collect "pip3 packages" "$pkg_dir/pip3.txt" pip3 list
    fi

    if command -v gem &>/dev/null; then
        run_collect "gem list" "$pkg_dir/gem.txt" gem list
    fi

    if command -v mise &>/dev/null; then
        run_collect "mise list" "$pkg_dir/mise.txt" mise list
    fi

    ok "Package lists collected"
}
