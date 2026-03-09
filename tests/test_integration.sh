#!/usr/bin/env bash
# Integration tests for macstate — runs actual snapshots, diffs, and exports
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MACSTATE="$PROJECT_DIR/macstate.sh"
TEST_DIR=$(mktemp -d /tmp/macstate_integration_XXXXXX)

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

begin_test() { CURRENT_TEST="$1"; echo "  TEST: $1"; }

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-$CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $msg — expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-$CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qF "$needle"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $msg — expected to contain '$needle'"
    fi
}

assert_file_exists() {
    local filepath="$1" msg="${2:-$CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$filepath" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $msg — file not found: $filepath"
    fi
}

assert_file_not_empty() {
    local filepath="$1" msg="${2:-$CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -s "$filepath" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $msg — file empty or not found: $filepath"
    fi
}

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo ""
echo "=== macstate integration tests ==="
echo "  Output: $TEST_DIR"
echo ""

# ── Test 1: Minimal snapshot with --only system-info ─────────────────────────

begin_test "minimal snapshot: --only system-info"
SNAP1_DIR="$TEST_DIR/snap1"
bash "$MACSTATE" --output "$SNAP1_DIR" --only system-info --no-filesystem 2>&1
rc=$?
assert_eq "0" "$rc" "exit code"

# Find the created snapshot directory
SNAP1=$(find "$SNAP1_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -n "$SNAP1" ]; then
    assert_file_exists "$SNAP1/system_info.txt" "system_info.txt exists"
    assert_file_not_empty "$SNAP1/system_info.txt" "system_info.txt not empty"
else
    TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: no snapshot directory created in $SNAP1_DIR"
fi

# ── Test 2: Filter validation ────────────────────────────────────────────────

begin_test "filter: --only system-info does not produce shell_env.txt"
if [ -n "${SNAP1:-}" ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ ! -f "$SNAP1/shell_env.txt" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: shell_env.txt should not exist with --only system-info"
    fi
else
    TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: no snapshot to check"
fi

# ── Test 3: Filesystem round-trip ────────────────────────────────────────────

begin_test "filesystem: --only filesystem --no-system"
SNAP2_DIR="$TEST_DIR/snap2"
bash "$MACSTATE" --output "$SNAP2_DIR" --only filesystem --no-system 2>&1
rc=$?
assert_eq "0" "$rc" "exit code"

SNAP2=$(find "$SNAP2_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -n "$SNAP2" ] && [ -f "$SNAP2/filesystem.db" ]; then
    file_count=$(sqlite3 "$SNAP2/filesystem.db" "SELECT COUNT(*) FROM files;" 2>/dev/null || echo "0")
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$file_count" -gt 0 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: filesystem.db has 0 file entries"
    fi

    begin_test "filesystem: metadata table has snapshot_time"
    snap_time=$(sqlite3 "$SNAP2/filesystem.db" "SELECT value FROM metadata WHERE key='snapshot_time';" 2>/dev/null || echo "")
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -n "$snap_time" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: no snapshot_time in metadata"
    fi
else
    TESTS_RUN=$((TESTS_RUN + 2)); TESTS_FAILED=$((TESTS_FAILED + 2))
    echo "  FAIL: filesystem.db not found"
fi

# ── Test 4: Diff round-trip ──────────────────────────────────────────────────

begin_test "diff: two snapshots produce diff output"
SNAP3_DIR="$TEST_DIR/snap3"
bash "$MACSTATE" --output "$SNAP3_DIR" --only system-info --no-filesystem 2>&1
sleep 1
bash "$MACSTATE" --output "$SNAP3_DIR" --only system-info --no-filesystem 2>&1

# Get both snapshot dirs
SNAPS=($(find "$SNAP3_DIR" -mindepth 1 -maxdepth 1 -type d | sort))
if [ "${#SNAPS[@]}" -ge 2 ]; then
    # Both need filesystem.db for diff — create empty ones
    for s in "${SNAPS[@]}"; do
        if [ ! -f "$s/filesystem.db" ]; then
            sqlite3 "$s/filesystem.db" "CREATE TABLE files (filepath TEXT PRIMARY KEY, filetype TEXT, size INTEGER, modified TEXT, permissions TEXT, owner TEXT, grp TEXT, inode INTEGER, symlink_target TEXT, sha256 TEXT); CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT); CREATE TABLE dotfile_contents (filepath TEXT PRIMARY KEY, content TEXT, sha256 TEXT);"
        fi
    done

    diff_output=$(bash "$MACSTATE" --diff "${SNAPS[0]}" "${SNAPS[1]}" 2>&1)
    rc=$?
    assert_eq "0" "$rc" "diff exit code"
    assert_contains "$diff_output" "Diff complete" "diff output contains completion message"
else
    TESTS_RUN=$((TESTS_RUN + 2)); TESTS_FAILED=$((TESTS_FAILED + 2))
    echo "  FAIL: could not create two snapshots for diff"
fi

# ── Test 5: JSON export ──────────────────────────────────────────────────────

begin_test "json export: produces valid JSON"
if [ -n "${SNAP2:-}" ] && [ -d "$SNAP2" ]; then
    bash "$MACSTATE" --export-json "$SNAP2" 2>&1
    rc=$?
    assert_eq "0" "$rc" "export-json exit code"

    if [ -f "$SNAP2/snapshot.json" ]; then
        python3 -m json.tool "$SNAP2/snapshot.json" > /dev/null 2>&1
        assert_eq "0" "$?" "valid JSON"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: snapshot.json not created"
    fi
else
    TESTS_RUN=$((TESTS_RUN + 2)); TESTS_FAILED=$((TESTS_FAILED + 2))
    echo "  FAIL: no snapshot for JSON export test"
fi

# ── Test 6: --no-filesystem + --diff should fail ────────────────────────────

begin_test "diff: fails when snapshots lack filesystem.db"
NO_DB_DIR="$TEST_DIR/snap_nodb"
mkdir -p "$NO_DB_DIR/snap_a" "$NO_DB_DIR/snap_b"
diff_output=$(bash "$MACSTATE" --diff "$NO_DB_DIR/snap_a" "$NO_DB_DIR/snap_b" 2>&1)
rc=$?
assert_eq "1" "$rc" "diff should fail without filesystem.db"

# ── Test 7: Unmatched --only produces warning ────────────────────────────────

begin_test "warning: --only nonexistent-collector"
SNAP_WARN_DIR="$TEST_DIR/snap_warn"
warn_output=$(bash "$MACSTATE" --output "$SNAP_WARN_DIR" --only nonexistent-name --no-filesystem 2>&1)
assert_contains "$warn_output" "No collectors matched" "unmatched --only warning"

# ── Test 8: Output directory permissions ─────────────────────────────────────

begin_test "permissions: snapshot directory is mode 700"
if [ -n "${SNAP1:-}" ] && [ -d "$SNAP1" ]; then
    perms=$(stat -f '%A' "$SNAP1" 2>/dev/null || stat -c '%a' "$SNAP1" 2>/dev/null)
    assert_eq "700" "$perms" "snapshot dir permissions"
else
    TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: no snapshot to check permissions"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=== Integration results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ==="

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
