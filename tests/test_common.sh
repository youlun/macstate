#!/usr/bin/env bash
# Unit tests for lib/common.sh

# Source common.sh (piped, so colors should be empty)
source "$PROJECT_DIR/lib/common.sh"

# ── parse_collector_header ───────────────────────────────────────────────────

begin_test "parse_collector_header: extracts LABEL"
TMPFILE=$(mktemp /tmp/macstate_test_XXXXXX.sh)
cat > "$TMPFILE" << 'EOF'
# LABEL: Test Collector
# REQUIRES_SUDO: false
collect_test() { true; }
EOF
parse_collector_header "$TMPFILE"
assert_eq "Test Collector" "$_COL_LABEL"
rm -f "$TMPFILE"

begin_test "parse_collector_header: extracts REQUIRES_SUDO=true"
TMPFILE=$(mktemp /tmp/macstate_test_XXXXXX.sh)
cat > "$TMPFILE" << 'EOF'
# LABEL: Sudo Collector
# REQUIRES_SUDO: true
collect_sudo() { true; }
EOF
parse_collector_header "$TMPFILE"
assert_eq "true" "$_COL_REQUIRES_SUDO"
rm -f "$TMPFILE"

begin_test "parse_collector_header: defaults REQUIRES_SUDO to false"
TMPFILE=$(mktemp /tmp/macstate_test_XXXXXX.sh)
cat > "$TMPFILE" << 'EOF'
# LABEL: No Sudo Line
collect_nosudo() { true; }
EOF
parse_collector_header "$TMPFILE"
assert_eq "false" "$_COL_REQUIRES_SUDO"
rm -f "$TMPFILE"

begin_test "parse_collector_header: derives name from filename"
TMPFILE=$(mktemp -d /tmp/macstate_test_XXXXXX)
cat > "$TMPFILE/03-defaults-domains.sh" << 'EOF'
# LABEL: Defaults Domains
# REQUIRES_SUDO: false
collect_defaults_domains() { true; }
EOF
parse_collector_header "$TMPFILE/03-defaults-domains.sh"
assert_eq "defaults-domains" "$_COL_NAME"
rm -rf "$TMPFILE"

begin_test "parse_collector_header: missing LABEL gives empty string"
TMPFILE=$(mktemp /tmp/macstate_test_XXXXXX.sh)
cat > "$TMPFILE" << 'EOF'
# REQUIRES_SUDO: false
collect_nolabel() { true; }
EOF
parse_collector_header "$TMPFILE"
assert_eq "" "$_COL_LABEL"
rm -f "$TMPFILE"

# ── should_run_collector ─────────────────────────────────────────────────────

begin_test "should_run_collector: no filters — always runs"
ONLY_COLLECTORS="" SKIP_COLLECTORS=""
should_run_collector "anything"
assert_eq "0" "$?" "should_run_collector with no filters"

begin_test "should_run_collector: --only match"
ONLY_COLLECTORS="homebrew,fonts"
should_run_collector "homebrew"
assert_eq "0" "$?" "should_run_collector --only homebrew"

begin_test "should_run_collector: --only miss"
ONLY_COLLECTORS="homebrew,fonts"
should_run_collector "network" && result=0 || result=1
assert_eq "1" "$result" "should_run_collector --only miss"

begin_test "should_run_collector: --skip match"
ONLY_COLLECTORS="" SKIP_COLLECTORS="fonts,packages"
should_run_collector "fonts" && result=0 || result=1
assert_eq "1" "$result" "should_run_collector --skip match"

begin_test "should_run_collector: --skip miss"
ONLY_COLLECTORS="" SKIP_COLLECTORS="fonts,packages"
should_run_collector "network"
assert_eq "0" "$?" "should_run_collector --skip miss"

# ── run_collect ──────────────────────────────────────────────────────────────

begin_test "run_collect: captures stdout"
TMPOUT=$(mktemp /tmp/macstate_test_XXXXXX.txt)
run_collect "test" "$TMPOUT" echo "hello world"
assert_contains "$(cat "$TMPOUT")" "hello world"
rm -f "$TMPOUT"

begin_test "run_collect: captures stderr"
TMPOUT=$(mktemp /tmp/macstate_test_XXXXXX.txt)
run_collect "test" "$TMPOUT" bash -c 'echo "stderr msg" >&2'
assert_contains "$(cat "$TMPOUT")" "stderr msg"
rm -f "$TMPOUT"

begin_test "run_collect: appends error marker on failure"
TMPOUT=$(mktemp /tmp/macstate_test_XXXXXX.txt)
run_collect "test" "$TMPOUT" false
assert_contains "$(cat "$TMPOUT")" "(command returned non-zero)"
rm -f "$TMPOUT"

# ── Color variables ──────────────────────────────────────────────────────────

begin_test "colors: empty when piped (not a TTY)"
# We're running in a pipe, so colors should be empty
assert_eq "" "$BOLD" "BOLD should be empty when piped"
assert_eq "" "$GREEN" "GREEN should be empty when piped"
assert_eq "" "$RED" "RED should be empty when piped"
