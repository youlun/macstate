#!/usr/bin/env bash
# Shared helpers for macstate collectors

# ── Colors (disabled when not a TTY) ─────────────────────────────────────────
# shellcheck disable=SC2034  # color vars are used by sourcing scripts
if [ -t 1 ]; then
    BOLD=$'\033[1m' GREEN=$'\033[32m' YELLOW=$'\033[33m' RED=$'\033[31m'
    BLUE=$'\033[34m' CYAN=$'\033[36m' DIM=$'\033[2m' RESET=$'\033[0m'
else
    BOLD='' GREEN='' YELLOW='' RED='' BLUE='' CYAN='' DIM='' RESET=''
fi

# ── Sudo detection ───────────────────────────────────────────────────────────
HAVE_SUDO=false
if [ "$EUID" -eq 0 ] 2>/dev/null || [ "$(id -u)" -eq 0 ]; then
    HAVE_SUDO=true
fi

REAL_USER="${SUDO_USER:-$USER}"
if [ "$HAVE_SUDO" = true ]; then
    REAL_HOME=$(dscl . -read "/Users/$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    REAL_HOME="${REAL_HOME:-/Users/$REAL_USER}"
else
    REAL_HOME="$HOME"
fi

# ── Output helpers ────────────────────────────────────────────────────────────
ok()   { echo "  ${GREEN}✓${RESET} $1"; }
warn() { echo "  ${YELLOW}!${RESET} $1"; }
fail() { echo "  ${RED}✗${RESET} $1"; }
info() { echo "  $1"; }

# ── Collector runner ──────────────────────────────────────────────────────────
# Usage: run_collect "label" "/path/to/output" command [args...]
# Runs a command, collects stdout+stderr to outfile, prints label.
run_collect() {
    local label="$1"
    local outfile="$2"
    shift 2
    info "${BLUE}->${RESET} $label"
    "$@" > "$outfile" 2>&1 || echo "(command returned non-zero)" >> "$outfile"
}

# ── Collector module loader ──────────────────────────────────────────────────
# Reads LABEL and REQUIRES_SUDO from comment headers in a collector script.
# Returns via globals: _COL_LABEL, _COL_REQUIRES_SUDO, _COL_NAME
parse_collector_header() {
    local file="$1"
    _COL_LABEL=$(grep '^# LABEL:' "$file" 2>/dev/null | head -1 | sed 's/^# LABEL: *//')
    _COL_REQUIRES_SUDO=$(grep '^# REQUIRES_SUDO:' "$file" 2>/dev/null | head -1 | sed 's/^# REQUIRES_SUDO: *//')
    _COL_REQUIRES_SUDO="${_COL_REQUIRES_SUDO:-false}"
    _COL_NAME=$(basename "$file" .sh | sed 's/^[0-9]*-//')
}

# Check if a collector should be skipped based on --only/--skip filters
# Globals: ONLY_COLLECTORS (comma-separated), SKIP_COLLECTORS (comma-separated)
should_run_collector() {
    local name="$1"
    if [ -n "${ONLY_COLLECTORS:-}" ]; then
        echo ",$ONLY_COLLECTORS," | grep -q ",$name," && return 0 || return 1
    fi
    if [ -n "${SKIP_COLLECTORS:-}" ]; then
        echo ",$SKIP_COLLECTORS," | grep -q ",$name," && return 1 || return 0
    fi
    return 0
}
