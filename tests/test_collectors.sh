#!/usr/bin/env bash
# Collector interface validation tests

source "$PROJECT_DIR/lib/common.sh"

# ── Every collector has required headers ─────────────────────────────────────

for col_file in "$PROJECT_DIR"/collectors/[0-9]*.sh; do
    [ -f "$col_file" ] || continue
    col_basename=$(basename "$col_file")

    begin_test "collector header: $col_basename has LABEL"
    label=$(grep -c '^# LABEL:' "$col_file")
    assert_eq "1" "$label" "$col_basename has LABEL header"

    begin_test "collector header: $col_basename has REQUIRES_SUDO"
    sudo_count=$(grep -c '^# REQUIRES_SUDO:' "$col_file")
    assert_eq "1" "$sudo_count" "$col_basename has REQUIRES_SUDO header"
done

# ── Every collector defines the expected function ────────────────────────────

for col_file in "$PROJECT_DIR"/collectors/[0-9]*.sh; do
    [ -f "$col_file" ] || continue
    col_basename=$(basename "$col_file")

    # Derive expected function name
    col_name=$(basename "$col_file" .sh | sed 's/^[0-9]*-//')
    func_name="collect_${col_name//-/_}"

    begin_test "collector function: $col_basename defines $func_name"

    # Source the collector
    source "$col_file"

    # Check function exists
    if declare -f "$func_name" > /dev/null 2>&1; then
        assert_eq "defined" "defined" "$func_name exists"
    else
        assert_eq "defined" "missing" "$col_basename does not define $func_name"
    fi
done

# ── Namespace check: only collect_* and _col_* functions added ───────────────

begin_test "collector namespace: no unexpected function names"
# Record functions before sourcing collectors
known_funcs="begin_test assert_eq assert_contains assert_not_contains assert_exit_code assert_file_exists assert_file_not_empty run_collect parse_collector_header should_run_collector ok warn fail info"
all_funcs=$(declare -F | awk '{print $3}')
bad_funcs=""
for f in $all_funcs; do
    # Skip known framework/helper functions
    is_known=false
    for k in $known_funcs; do
        [ "$f" = "$k" ] && is_known=true && break
    done
    $is_known && continue

    # Only collect_* and _col_* should exist from collectors
    case "$f" in
        collect_*|_col_*) ;;
        *) bad_funcs="$bad_funcs $f" ;;
    esac
done
assert_eq "" "$bad_funcs" "unexpected functions from collectors:$bad_funcs"

# ── Dotfile list sync: lib/dotfiles.txt exists and is non-empty ──────────────

begin_test "dotfile list: lib/dotfiles.txt exists"
assert_file_exists "$PROJECT_DIR/lib/dotfiles.txt"

begin_test "dotfile list: lib/dotfiles.txt is non-empty"
assert_file_not_empty "$PROJECT_DIR/lib/dotfiles.txt"

begin_test "dotfile list: contains expected dotfiles"
dotfile_content=$(cat "$PROJECT_DIR/lib/dotfiles.txt")
assert_contains "$dotfile_content" ".zshrc"
assert_contains "$dotfile_content" ".gitconfig"
assert_contains "$dotfile_content" ".ssh/config"
