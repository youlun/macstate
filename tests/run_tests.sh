#!/usr/bin/env bash
# Minimal bash test runner for macstate
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Assert helpers ───────────────────────────────────────────────────────────

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

begin_test() {
    CURRENT_TEST="$1"
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-$CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $msg"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
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
        echo "    got: '$haystack'"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="${3:-$CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! echo "$haystack" | grep -qF "$needle"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $msg — expected NOT to contain '$needle'"
    fi
}

assert_exit_code() {
    local expected_code="$1"
    shift
    local msg="${CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))
    "$@" >/dev/null 2>&1
    local actual_code=$?
    if [ "$actual_code" -eq "$expected_code" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $msg — expected exit $expected_code, got $actual_code"
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

# ── Run test files ───────────────────────────────────────────────────────────

echo "=== macstate bash tests ==="
echo ""

for test_file in "$SCRIPT_DIR"/test_common.sh "$SCRIPT_DIR"/test_collectors.sh; do
    if [ -f "$test_file" ]; then
        echo "--- $(basename "$test_file") ---"
        source "$test_file"
        echo ""
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo "=== Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ==="

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
