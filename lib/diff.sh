#!/usr/bin/env bash
# Diff logic for macstate

run_diff() {
    local snap1="$1"
    local snap2="$2"
    local filter="${3:-}"

    local db1="$snap1/filesystem.db"
    local db2="$snap2/filesystem.db"

    if [ ! -f "$db1" ] || [ ! -f "$db2" ]; then
        fail "Both snapshot directories must contain filesystem.db"
        return 1
    fi

    # Store diff DB in a diffs/ directory alongside snapshots
    local base_dir
    base_dir="$(dirname "$snap1")"
    local diffs_dir="$base_dir/diffs"
    mkdir -p "$diffs_dir"

    local snap1_name snap2_name
    snap1_name="$(basename "$snap1")"
    snap2_name="$(basename "$snap2")"
    local diff_db="$diffs_dir/DIFF_${snap1_name}_vs_${snap2_name}.db"
    local diff_txt="$diffs_dir/DIFF_${snap1_name}_vs_${snap2_name}.txt"

    echo ""
    echo "${CYAN}══════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}  macstate diff${RESET}"
    echo "  ${DIM}Before: ${snap1}${RESET}"
    echo "  ${DIM}After:  ${snap2}${RESET}"
    if [ -n "$filter" ]; then
        echo "  ${DIM}Filter: ${filter}%${RESET}"
    fi
    echo "${CYAN}══════════════════════════════════════════════════════${RESET}"
    echo ""

    info "${BLUE}->${RESET} Building diff database..."

    rm -f "$diff_db"

    # Reject filter values with characters that could cause SQL injection
    local safe_path_re='^[a-zA-Z0-9_. /-]+$'
    if [ -n "$filter" ] && [[ ! "$filter" =~ $safe_path_re ]]; then
        fail "Filter path contains invalid characters"
        return 1
    fi

    local filter_where=""
    if [ -n "$filter" ]; then
        filter_where="WHERE filepath LIKE '${filter}%'"
    fi

    sqlite3 "$diff_db" << DIFFSQL
ATTACH DATABASE '${db1}' AS before_snap;
ATTACH DATABASE '${db2}' AS after_snap;

CREATE TABLE snap_a AS SELECT * FROM before_snap.files ${filter_where:-};
CREATE TABLE snap_b AS SELECT * FROM after_snap.files ${filter_where:-};

CREATE INDEX idx_a_path ON snap_a(filepath);
CREATE INDEX idx_b_path ON snap_b(filepath);

-- Copy metadata
CREATE TABLE meta_a AS SELECT * FROM before_snap.metadata;
CREATE TABLE meta_b AS SELECT * FROM after_snap.metadata;

-- New files
CREATE VIEW new_files AS
SELECT b.* FROM snap_b b
LEFT JOIN snap_a a ON b.filepath = a.filepath
WHERE a.filepath IS NULL;

-- Deleted files
CREATE VIEW deleted_files AS
SELECT a.* FROM snap_a a
LEFT JOIN snap_b b ON a.filepath = b.filepath
WHERE b.filepath IS NULL;

-- Changed files (size, time, permissions, or owner)
CREATE VIEW changed_files AS
SELECT
  a.filepath,
  a.size AS old_size,       b.size AS new_size,
  a.modified AS old_modified, b.modified AS new_modified,
  a.permissions AS old_perms, b.permissions AS new_perms,
  a.owner AS old_owner,      b.owner AS new_owner
FROM snap_a a
JOIN snap_b b ON a.filepath = b.filepath
WHERE a.size != b.size
   OR a.modified != b.modified
   OR a.permissions != b.permissions
   OR a.owner != b.owner;

-- Summary
CREATE VIEW diff_summary AS
SELECT
  (SELECT COUNT(*) FROM new_files)     AS new_files,
  (SELECT COUNT(*) FROM deleted_files) AS deleted_files,
  (SELECT COUNT(*) FROM changed_files) AS changed_files,
  (SELECT COUNT(*) FROM snap_a)        AS total_before,
  (SELECT COUNT(*) FROM snap_b)        AS total_after;

-- Content changes: SHA-256 differs (even if size/mtime match)
CREATE VIEW content_changes AS
SELECT
  a.filepath,
  a.size AS old_size, b.size AS new_size,
  a.sha256 AS old_sha256, b.sha256 AS new_sha256
FROM snap_a a
JOIN snap_b b ON a.filepath = b.filepath
WHERE a.sha256 IS NOT NULL AND b.sha256 IS NOT NULL
  AND a.sha256 != b.sha256;

-- Symlink target changes
CREATE VIEW symlink_changes AS
SELECT
  a.filepath,
  a.symlink_target AS old_target,
  b.symlink_target AS new_target
FROM snap_a a
JOIN snap_b b ON a.filepath = b.filepath
WHERE a.filetype = 'l' AND b.filetype = 'l'
  AND COALESCE(a.symlink_target, '') != COALESCE(b.symlink_target, '');

-- Dotfile content tables and views
CREATE TABLE dotfiles_a AS SELECT * FROM before_snap.dotfile_contents;
CREATE TABLE dotfiles_b AS SELECT * FROM after_snap.dotfile_contents;

CREATE VIEW new_dotfiles AS
SELECT b.* FROM dotfiles_b b
LEFT JOIN dotfiles_a a ON b.filepath = a.filepath
WHERE a.filepath IS NULL;

CREATE VIEW deleted_dotfiles AS
SELECT a.* FROM dotfiles_a a
LEFT JOIN dotfiles_b b ON a.filepath = b.filepath
WHERE b.filepath IS NULL;

CREATE VIEW changed_dotfiles AS
SELECT a.filepath,
       a.sha256 AS old_sha256, b.sha256 AS new_sha256
FROM dotfiles_a a
JOIN dotfiles_b b ON a.filepath = b.filepath
WHERE a.sha256 != b.sha256;

DETACH DATABASE before_snap;
DETACH DATABASE after_snap;
DIFFSQL

    info "${BLUE}->${RESET} Generating report..."

    {
        echo "macstate Diff Report"
        echo "Generated: $(date)"
        echo "Before: $snap1"
        echo "After:  $snap2"
        [ -n "$filter" ] && echo "Filter: ${filter}%"
        echo "============================================================"
        echo ""

        echo "=== SUMMARY ==="
        sqlite3 -header -column "$diff_db" "SELECT * FROM diff_summary;"
        echo ""

        echo "================================================================"
        echo "  NEW FILES"
        echo "================================================================"
        local new_count
        new_count=$(sqlite3 "$diff_db" "SELECT COUNT(*) FROM new_files;")
        if [ "$new_count" -gt 0 ]; then
            echo "($new_count new files)"
            echo ""
            echo "--- Config files ---"
            sqlite3 -column "$diff_db" \
                "SELECT filepath, size, modified FROM new_files
                 WHERE filepath LIKE '%.plist' OR filepath LIKE '%.conf'
                    OR filepath LIKE '%.json' OR filepath LIKE '%.toml'
                    OR filepath LIKE '%.yaml' OR filepath LIKE '%.yml'
                 ORDER BY modified DESC LIMIT 100;"
            echo ""
            echo "--- All other new files (top 200) ---"
            sqlite3 -column "$diff_db" \
                "SELECT filepath, size, modified FROM new_files
                 WHERE filepath NOT LIKE '%.plist' AND filepath NOT LIKE '%.conf'
                   AND filepath NOT LIKE '%.json' AND filepath NOT LIKE '%.toml'
                   AND filepath NOT LIKE '%.yaml' AND filepath NOT LIKE '%.yml'
                 ORDER BY modified DESC LIMIT 200;"
        else
            echo "(none)"
        fi
        echo ""

        echo "================================================================"
        echo "  DELETED FILES"
        echo "================================================================"
        local del_count
        del_count=$(sqlite3 "$diff_db" "SELECT COUNT(*) FROM deleted_files;")
        if [ "$del_count" -gt 0 ]; then
            echo "($del_count deleted files — showing first 200)"
            sqlite3 -column "$diff_db" \
                "SELECT filepath, size FROM deleted_files ORDER BY filepath LIMIT 200;"
        else
            echo "(none)"
        fi
        echo ""

        echo "================================================================"
        echo "  CHANGED FILES"
        echo "================================================================"
        local chg_count
        chg_count=$(sqlite3 "$diff_db" "SELECT COUNT(*) FROM changed_files;")
        if [ "$chg_count" -gt 0 ]; then
            echo "($chg_count changed files)"
            echo ""
            echo "--- Preferences ---"
            sqlite3 -header -column "$diff_db" \
                "SELECT filepath, old_size, new_size, old_modified, new_modified
                 FROM changed_files
                 WHERE filepath LIKE '%/Preferences/%'
                 ORDER BY new_modified DESC LIMIT 100;"
            echo ""
            echo "--- Other changes (top 200) ---"
            sqlite3 -header -column "$diff_db" \
                "SELECT filepath, old_size, new_size, old_modified, new_modified
                 FROM changed_files
                 WHERE filepath NOT LIKE '%/Preferences/%'
                 ORDER BY new_modified DESC LIMIT 200;"
        else
            echo "(none)"
        fi
        echo ""

    } > "$diff_txt"

    # Per-domain preference diffs
    info "${BLUE}->${RESET} Diffing preference values..."
    local pref_changes=0

    {
        echo ""
        echo "================================================================"
        echo "  PREFERENCE VALUE CHANGES"
        echo "================================================================"
        echo ""

        # Collect all txt/plist files from both snapshots (using subshells to avoid cd side effects)
        local all_files
        all_files=$(
            ( cd "$snap1" && find . -type f \( -name "*.txt" -o -name "*.plist" \) 2>/dev/null )
            ( cd "$snap2" && find . -type f \( -name "*.txt" -o -name "*.plist" \) 2>/dev/null )
        )
        all_files=$(echo "$all_files" | sort -u)

        while IFS= read -r file; do
            [ -z "$file" ] && continue
            [[ "$file" == *"DIFF"* || "$file" == *"filesystem.db"* ]] && continue

            local file_a="$snap1/$file"
            local file_b="$snap2/$file"

            if [ ! -f "$file_a" ]; then
                echo ">>> NEW: $file"
                pref_changes=$((pref_changes + 1))
            elif [ ! -f "$file_b" ]; then
                echo ">>> REMOVED: $file"
                pref_changes=$((pref_changes + 1))
            else
                local diff_result
                diff_result=$(diff -- "$file_a" "$file_b" 2>/dev/null || true)
                if [ -n "$diff_result" ]; then
                    echo "=========================================================="
                    echo "CHANGED: $file"
                    echo "=========================================================="
                    echo "$diff_result"
                    echo ""
                    pref_changes=$((pref_changes + 1))
                fi
            fi
        done <<< "$all_files"
    } >> "$diff_txt"

    cat "$diff_txt"

    echo ""
    echo "${CYAN}══════════════════════════════════════════════════════${RESET}"
    echo "${GREEN}  Diff complete! ${pref_changes} preference changes found.${RESET}"
    echo ""
    echo "    Report: ${diff_txt}"
    echo "    Diff DB: ${diff_db}"
    echo ""
    echo "  ${YELLOW}Query the diff:${RESET}"
    echo "    ${CYAN}sqlite3 -header -column ${diff_db}${RESET}"
    echo "    ${DIM}SELECT * FROM new_files LIMIT 20;${RESET}"
    echo "    ${DIM}SELECT * FROM changed_files LIMIT 50;${RESET}"
    echo "    ${DIM}SELECT * FROM content_changes;${RESET}"
    echo "    ${DIM}SELECT * FROM symlink_changes;${RESET}"
    echo "${CYAN}══════════════════════════════════════════════════════${RESET}"
}
