# LABEL: NSGlobalDomain defaults
# REQUIRES_SUDO: false

collect_defaults_global() {
    local outdir="$1"
    run_collect "NSGlobalDomain" "$outdir/defaults_NSGlobalDomain.txt" defaults read NSGlobalDomain
}
