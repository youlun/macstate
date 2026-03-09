# shellcheck shell=bash
# LABEL: Filesystem index
# REQUIRES_SUDO: false

collect_filesystem() {
    # shellcheck disable=SC2034  # required by collector interface
    local outdir="$1"
    local db="$2"

    local scanner="$SCRIPT_DIR/lib/fs_index.py"

    if ! command -v python3 &>/dev/null; then
        warn "python3 not found — skipping filesystem scan"
        return 1
    fi

    info "${BLUE}->${RESET} Indexing filesystem..."

    local scanner_args=(--db "$db" --home "$REAL_HOME")
    if [ "${NO_SYSTEM:-false}" = true ]; then
        scanner_args+=(--no-system)
    fi

    python3 "$scanner" "${scanner_args[@]}"

    if [ -f "$db" ]; then
        local indexed_count file_count dir_count db_size
        indexed_count=$(sqlite3 "$db" "SELECT COUNT(*) FROM files;" 2>/dev/null || echo "0")
        file_count=$(sqlite3 "$db" "SELECT COUNT(*) FROM files WHERE filetype='f';" 2>/dev/null || echo "0")
        dir_count=$(sqlite3 "$db" "SELECT COUNT(*) FROM files WHERE filetype='d';" 2>/dev/null || echo "0")
        db_size=$(du -h "$db" | cut -f1)

        if [ "$indexed_count" -lt 1000 ]; then
            warn "Only ${indexed_count} files indexed — try running with sudo"
        fi

        ok "Indexed ${indexed_count} entries (${file_count} files, ${dir_count} dirs) — ${db_size}"
    fi
}
