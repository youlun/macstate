# macstate

Read `ARCHITECTURE.md` first for the full design reference.

## Quick orientation

- **Default snapshot dir:** `~/MacSnapshots/<timestamp>/`
- **Main entry:** `macstate.sh` — arg parsing, mode dispatch, collector loader
- **Shared helpers:** `lib/common.sh` — colors, `run_collect`, `parse_collector_header`
- **Filesystem indexer:** `lib/fs_index.py` — Python 3 walker, writes SQLite
- **Diff engine:** `lib/diff.sh` — compares two snapshots via SQL views + text diff
- **JSON export:** `lib/json_export.py` — converts snapshot to JSON
- **HTML viewer:** `lib/html_export.py` + `lib/viewer_template.html` — self-contained HTML snapshot/diff viewer
- **Collector modules:** `collectors/00-*.sh` through `collectors/19-*.sh` — each collects one category of system state

## Key conventions

### Collector module interface

Every `collectors/NN-name.sh` must have:
```bash
# LABEL: Human-readable name
# REQUIRES_SUDO: true|false

collect_name_with_underscores() {
    local outdir="$1"
    local db="$2"
    # ... use run_collect or write directly
}
```

- Function name = `collect_` + filename without number prefix, hyphens become underscores
- Example: `03-defaults-domains.sh` defines `collect_defaults_domains()`
- Private helpers use `_col_` prefix (e.g., `_col_scutil`)
- Output goes to `$outdir/` — text files, subdirectories, or the SQLite DB
- Must be **read-only**: never modify system state, never write outside `$outdir`

### Filesystem indexer (Python)

- Requires Python 3.9+ (uses `from __future__ import annotations`)
- Uses `isolation_level=None` (autocommit) with manual `BEGIN TRANSACTION` / `COMMIT`
- Schema: `files`, `metadata`, `dotfile_contents` tables
- All timestamps are UTC ISO-8601 (`%Y-%m-%dT%H:%M:%SZ`)
- Sensitive files (SSH/GPG private keys) are excluded from hashing
- Cache/log directories are excluded by default via `DEFAULT_EXCLUDES`
- The dotfile content list is in `lib/dotfiles.txt` (single source of truth), loaded by both `fs_index.py` and `collectors/17-dotfile-contents.sh`

### Diff engine

- Creates a separate `DIFF_*.db` in a `diffs/` directory alongside snapshots
- Uses SQL views (`new_files`, `deleted_files`, `changed_files`, `content_changes`, `symlink_changes`, `changed_dotfiles`)
- Filter values are whitelist-validated against `^[a-zA-Z0-9_. /-]+$`
- Report is written to `DIFF_*.txt` and displayed on terminal

### HTML viewer

- `--view <snap>` for single snapshot, `--view <snap1> <snap2>` for diff
- Data embedded as JSON in HTML, rendered client-side with vanilla JS
- Template lives in `lib/viewer_template.html` (separate file, not Python string)
- Paths passed to SQLite ATTACH must be validated (no single quotes)
- `diffs/` directory must use `mode=0o700` to match snapshot security model

## Safety rules

- All collectors must be **non-destructive** (read-only system queries)
- Secrets in `env` output are **redacted** (see `16-shell-env.sh`)
- Output directory uses `chmod 700` (owner-only access)
- `HOMEBREW_NO_AUTO_UPDATE=1` is set before any brew commands
- Never hash private key files (enforced by `HASH_EXCLUDE_*` in fs_index.py)

## Common pitfalls

- The `--diff` arg parser uses `shift 2` inside the case + the outer loop's `shift` = 3 total shifts for the 3 consumed tokens (`--diff`, snap1, snap2). Don't change the shift count without understanding the loop structure.
- The `--view` arg parser peeks at `$3` to detect optional second snapshot — uses `shift 2` or `shift 1` accordingly. Same outer-loop `shift` applies.
- `run_collect` appends `(command returned non-zero)` to output files on failure. This is intentional but means the diff engine will flag it as a content change.
- Collector modules are `source`d into the main shell — all variable/function names are global. Use `local` and `_col_` prefixes.
- `store_metadata()` in fs_index.py runs inside the transaction so an interrupted scan won't leave a partial DB with metadata but no files.

## Development

### Running tests
```bash
make lint              # shellcheck + ruff
make test              # bash unit tests + pytest
make test-integration  # integration tests (runs real snapshots)
make test-all          # lint + test + test-integration
ruff format lib/ tests/ # auto-fix Python formatting
```

### Pre-commit hook
```bash
git config core.hooksPath .githooks   # activate
git commit --no-verify                # skip if needed
```

### CI
GitHub Actions runs on every push to main and all PRs: lint on ubuntu, unit tests on ubuntu, bash tests + integration on macOS.
