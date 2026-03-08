# LABEL: Per-domain plist exports
# REQUIRES_SUDO: false

collect_defaults_domains() {
    local outdir="$1"
    local domain_dir="$outdir/defaults_domains"
    mkdir -p "$domain_dir"

    local domains domain_count=0 domain_total
    domains=$(defaults domains 2>/dev/null | tr ',' '\n' | sed 's/^ *//')
    domain_total=$(echo "$domains" | wc -l | tr -d ' ')

    while IFS= read -r domain; do
        [ -z "$domain" ] && continue
        domain_count=$((domain_count + 1))
        local safe_name="${domain//\//_}"
        defaults read "$domain" > "$domain_dir/${safe_name}.txt" 2>/dev/null || true
        printf '\r  %s %d / %d domains' "${BLUE}->${RESET}" "$domain_count" "$domain_total"
    done <<< "$domains"
    echo ""
    ok "Exported ${domain_count} domains"
}
