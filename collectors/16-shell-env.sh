# LABEL: Shell environment
# REQUIRES_SUDO: false

collect_shell_env() {
    local outdir="$1"
    run_collect "shell environment" "$outdir/shell_env.txt" _col_shell_env
}

_col_shell_env() {
    echo "=== Default shell ==="
    echo "  \$SHELL: ${SHELL:-unknown}"
    dscl . -read "/Users/$REAL_USER" UserShell 2>/dev/null || echo "  (dscl unavailable)"
    echo ""

    echo "=== Shell versions ==="
    for sh in zsh bash fish; do
        local path
        path=$(which "$sh" 2>/dev/null || true)
        if [ -n "$path" ]; then
            echo "  $sh: $path ($("$path" --version 2>&1 | head -1))"
        fi
    done
    echo ""

    echo "=== PATH ==="
    echo "$PATH" | tr ':' '\n' | nl
    echo ""

    echo "=== Environment variables (secrets redacted, transient filtered) ==="
    env | grep -Ev '^(TMPDIR=|_=|SHLVL=|OLDPWD=|TERM_SESSION_ID=|LaunchInstanceID=|SECURITYSESSIONID=|XPC_)' \
        | sort \
        | sed -E 's/^(.*(_TOKEN|_SECRET|_KEY|_PASSWORD|_CREDENTIAL|_API_KEY|_URL|_URI|_DSN|_CONNECTION_STRING|API_KEY|ANTHROPIC_|AWS_SECRET|GITHUB_TOKEN|GH_TOKEN|NPM_TOKEN|HOMEBREW_GITHUB_API_TOKEN)=).*/\1<REDACTED>/'
}
