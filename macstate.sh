#!/usr/bin/env bash
# =============================================================================
# macstate  v0.1
# =============================================================================
# Captures macOS system state for diffing and comparison.
#
# Usage:
#   ./macstate.sh                              # Capture system state
#   sudo ./macstate.sh                         # Full capture (with sudo)
#   ./macstate.sh --output /path               # Custom output location
#   ./macstate.sh --only homebrew,shell-env     # Run specific collectors
#   ./macstate.sh --skip fonts,packages         # Skip specific collectors
#   ./macstate.sh --no-filesystem               # Preference-only capture
#   ./macstate.sh --diff <snap1> <snap2>        # Diff two snapshots
#   ./macstate.sh --diff <s1> <s2> --filter ~/  # Diff with path filter
#   ./macstate.sh --query <snapshot>             # Interactive SQL query
#   ./macstate.sh --help                         # Show help
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_VERSION="0.1"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ── Help ──────────────────────────────────────────────────────────────────────

show_help() {
    cat << 'EOF'
macstate v0.1 — macOS system state capture tool

USAGE:
  macstate.sh [MODE] [OPTIONS]

MODES:
  (default)                  Capture system state
  --diff <snap1> <snap2>     Diff two snapshots
  --query <snapshot>         Interactive SQLite query mode
  --export-json <snapshot>   Export snapshot as JSON
  --help                     Show this help

SNAPSHOT OPTIONS:
  --output DIR               Output base directory (default: ~/MacSnapshots)
  --only COLLECTOR,...       Run only named collectors
  --skip COLLECTOR,...       Skip named collectors
  --no-filesystem            Skip filesystem index (fast preference-only)
  --no-system                Skip /System and /Library scans (user-only)

DIFF OPTIONS:
  --filter PREFIX            Only show changes under this path prefix

AVAILABLE COLLECTORS:
  system-info, filesystem, defaults-global, defaults-domains, defaults-apps,
  system-plists, systemsetup, network, power, security, login-items, sharing,
  input, appearance, apps, homebrew, shell-env, dotfile-contents, packages, fonts

QUERY EXAMPLES:
  -- Files modified in last 2 hours
  SELECT filepath FROM files
    WHERE modified > datetime('now', '-2 hours');

  -- New files between snapshots (run on diff DB)
  SELECT * FROM new_files WHERE filepath LIKE '%.plist';

  -- Dotfile content changes
  SELECT filepath FROM changed_dotfiles;

  -- Files with different content but same size
  SELECT filepath FROM content_changes WHERE old_size = new_size;
EOF
    exit 0
}

# ── Argument parsing ──────────────────────────────────────────────────────────

MODE="snapshot"
OUTPUT_DIR=""
ONLY_COLLECTORS=""
SKIP_COLLECTORS=""
NO_FILESYSTEM=false
NO_SYSTEM=false
DIFF_SNAP1=""
DIFF_SNAP2=""
DIFF_FILTER=""
QUERY_SNAP=""
EXPORT_JSON_SNAP=""

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)       show_help ;;
        --diff)          MODE="diff"; DIFF_SNAP1="${2:-}"; DIFF_SNAP2="${3:-}"; shift 2 ;;
        --query)         MODE="query"; QUERY_SNAP="${2:-}"; shift ;;
        --export-json)   MODE="export-json"; EXPORT_JSON_SNAP="${2:-}"; shift ;;
        --output)        OUTPUT_DIR="${2:-}"; shift ;;
        --only)          ONLY_COLLECTORS="${2:-}"; shift ;;
        --skip)          SKIP_COLLECTORS="${2:-}"; shift ;;
        --filter)        DIFF_FILTER="${2:-}"; shift ;;
        --no-filesystem) NO_FILESYSTEM=true ;;
        --no-system)     NO_SYSTEM=true ;;
        *)               echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

export ONLY_COLLECTORS SKIP_COLLECTORS NO_FILESYSTEM NO_SYSTEM

# ── Query mode ────────────────────────────────────────────────────────────────

if [ "$MODE" = "query" ]; then
    if [ -z "$QUERY_SNAP" ] || [ ! -f "$QUERY_SNAP/filesystem.db" ]; then
        fail "Usage: $0 --query <snapshot_dir> (must contain filesystem.db)"
        exit 1
    fi
    echo "${CYAN}Interactive Query Mode — ${QUERY_SNAP}/filesystem.db${RESET}"
    echo "${DIM}Type SQL queries, or .quit to exit. Run $0 --help for examples.${RESET}"
    sqlite3 -header -column "$QUERY_SNAP/filesystem.db"
    exit 0
fi

# ── Export JSON mode ──────────────────────────────────────────────────────────

if [ "$MODE" = "export-json" ]; then
    if [ -z "$EXPORT_JSON_SNAP" ] || [ ! -d "$EXPORT_JSON_SNAP" ]; then
        fail "Usage: $0 --export-json <snapshot_dir>"
        exit 1
    fi
    python3 "$SCRIPT_DIR/lib/json_export.py" "$EXPORT_JSON_SNAP"
    exit $?
fi

# ── Diff mode ─────────────────────────────────────────────────────────────────

if [ "$MODE" = "diff" ]; then
    source "$SCRIPT_DIR/lib/diff.sh"
    run_diff "$DIFF_SNAP1" "$DIFF_SNAP2" "$DIFF_FILTER"
    exit $?
fi

# ── Snapshot mode ─────────────────────────────────────────────────────────────

BASE_DIR="${OUTPUT_DIR:-$REAL_HOME/MacSnapshots}"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
OUTDIR="$BASE_DIR/$TIMESTAMP"
DB="$OUTDIR/filesystem.db"

mkdir -p "$BASE_DIR"
chmod 700 "$BASE_DIR" 2>/dev/null || true
# shellcheck disable=SC2174  # -m intentionally applies to leaf only; parent handled above
mkdir -p -m 700 "$OUTDIR"

if [ "$HAVE_SUDO" = true ]; then
    chown -R "$REAL_USER" "$OUTDIR" 2>/dev/null || true
fi

echo ""
echo "${CYAN}══════════════════════════════════════════════════════${RESET}"
echo "${BOLD}  macstate v${SCRIPT_VERSION}${RESET}"
echo "  ${DIM}Output: ${OUTDIR}${RESET}"
if [ "$HAVE_SUDO" = true ]; then
    echo "  ${DIM}Running as root — full capture enabled${RESET}"
else
    echo "  ${YELLOW}Running without sudo — some collectors will be partial${RESET}"
fi
echo "${CYAN}══════════════════════════════════════════════════════${RESET}"
echo ""

# ── Load and run collectors ──────────────────────────────────────────────────

COL_COUNT=0
COL_TOTAL=0
COL_SKIPPED=0

# Count total collectors
for col_file in "$SCRIPT_DIR"/collectors/[0-9]*.sh; do
    [ -f "$col_file" ] || continue
    COL_TOTAL=$((COL_TOTAL + 1))
done

for col_file in "$SCRIPT_DIR"/collectors/[0-9]*.sh; do
    [ -f "$col_file" ] || continue

    parse_collector_header "$col_file"
    COL_COUNT=$((COL_COUNT + 1))

    # Check --only / --skip filters
    if ! should_run_collector "$_COL_NAME"; then
        info "${DIM}[${COL_COUNT}/${COL_TOTAL}] Skipped: ${_COL_LABEL} (filtered)${RESET}"
        COL_SKIPPED=$((COL_SKIPPED + 1))
        continue
    fi

    # Check --no-filesystem
    if [ "$NO_FILESYSTEM" = true ] && [ "$_COL_NAME" = "filesystem" ]; then
        info "${DIM}[${COL_COUNT}/${COL_TOTAL}] Skipped: ${_COL_LABEL} (--no-filesystem)${RESET}"
        COL_SKIPPED=$((COL_SKIPPED + 1))
        continue
    fi

    # Check sudo requirement
    if [ "$_COL_REQUIRES_SUDO" = "true" ] && [ "$HAVE_SUDO" != "true" ]; then
        info "${YELLOW}[${COL_COUNT}/${COL_TOTAL}] Skipped: ${_COL_LABEL} (needs sudo)${RESET}"
        COL_SKIPPED=$((COL_SKIPPED + 1))
        continue
    fi

    echo "${GREEN}[${COL_COUNT}/${COL_TOTAL}]${RESET} ${BOLD}${_COL_LABEL}${RESET}"

    # Source and run the collector function
    source "$col_file"
    # Derive function name from filename: 01-filesystem.sh -> collect_filesystem
    func_name="collect_${_COL_NAME//-/_}"
    if declare -f "$func_name" > /dev/null 2>&1; then
        "$func_name" "$OUTDIR" "$DB"
    else
        warn "No function $func_name found in $col_file"
    fi
done

# ── Warn if --only matched nothing ────────────────────────────────────────────

COL_RAN=$((COL_COUNT - COL_SKIPPED))
if [ -n "${ONLY_COLLECTORS:-}" ] && [ "$COL_RAN" -eq 0 ]; then
    echo ""
    warn "No collectors matched '${ONLY_COLLECTORS}'. Valid names:"
    for _vf in "$SCRIPT_DIR"/collectors/[0-9]*.sh; do
        [ -f "$_vf" ] || continue
        echo "    $(basename "$_vf" .sh | sed 's/^[0-9]*-//')"
    done
    echo ""
fi

# ── Fix ownership ────────────────────────────────────────────────────────────

if [ "$HAVE_SUDO" = true ]; then
    chown -R "$REAL_USER" "$OUTDIR" 2>/dev/null || true
fi

# ── Summary ──────────────────────────────────────────────────────────────────

SNAP_SIZE=$(du -sh "$OUTDIR" 2>/dev/null | cut -f1)

DB_ENTRIES="n/a"
if [ -f "$DB" ]; then
    DB_ENTRIES=$(sqlite3 "$DB" "SELECT COUNT(*) FROM files;" 2>/dev/null || echo "0")
fi

echo ""
echo "${CYAN}══════════════════════════════════════════════════════${RESET}"
echo "${GREEN}  Capture complete!${RESET}"
echo ""
echo "    Location:    ${OUTDIR}"
echo "    DB entries:  ${DB_ENTRIES} filesystem objects"
echo "    Collectors:  $((COL_COUNT - COL_SKIPPED))/${COL_TOTAL} run"
echo "    Total size:  ${SNAP_SIZE}"
echo ""
echo "  ${YELLOW}Diff with another snapshot:${RESET}"
echo "    ${CYAN}$0 --diff ${OUTDIR} <other_snapshot>${RESET}"
echo ""
echo "  ${YELLOW}Query this snapshot:${RESET}"
echo "    ${CYAN}$0 --query ${OUTDIR}${RESET}"
echo "${CYAN}══════════════════════════════════════════════════════${RESET}"
