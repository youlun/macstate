# Architecture: macstate

## Purpose

Capture a complete, diffable snapshot of macOS system state — preferences, installed software, filesystem structure, dotfile contents, and system configuration. Designed for tracking what changes between system setups, updates, or bootstrap runs.

The tool is **read-only** and **non-destructive**. It never modifies system state.

## Design decisions

**Why shell + Python (not pure shell or pure Python)?**
Collectors are shell scripts because they mostly run macOS CLI tools (`defaults`, `networksetup`, `pmset`, `brew`). The filesystem indexer is Python because `os.walk` + SQLite + SHA-256 hashing is significantly faster and more reliable than shell-based alternatives. Apple deprecated system Ruby, so Python 3 (bundled with Xcode CLT) is the right choice.

**Why SQLite for the filesystem, text files for preferences?**
The filesystem index can contain 200K+ entries — too large for text. SQLite enables efficient diffing via SQL joins and supports ad-hoc queries. Preferences are small text outputs from `defaults read` — plain text is easier to diff, read, and version-control.

**Why modular collectors?**
Each collector is independent, can be skipped (`--skip`), selected (`--only`), and has its own sudo requirement. This lets users take fast partial snapshots (`--only homebrew,shell-env`) and makes the tool easy to extend.

## Component overview

```
macstate.sh                Main driver: arg parsing, mode dispatch, collector loader
lib/
  common.sh                Shared helpers: colors, run_collect, collector header parser
  fs_index.py              Python filesystem indexer: os.walk → SQLite
  diff.sh                  Diff engine: SQL views + text comparison
  json_export.py           JSON export mode
collectors/
  00-system-info.sh        sw_vers, uname, hardware profile
  01-filesystem.sh         Invokes fs_index.py
  02-defaults-global.sh    NSGlobalDomain preferences
  03-defaults-domains.sh   Per-domain defaults (text format)
  04-defaults-apps.sh      Curated list of key app domains
  05-system-plists.sh      /Library/Preferences plists
  06-systemsetup.sh        systemsetup commands (requires sudo)
  07-network.sh            scutil, networksetup per-service
  08-power.sh              pmset power settings
  09-security.sh           Firewall, Gatekeeper, SIP, FileVault, Secure Boot
  10-login-items.sh        LaunchAgents, LaunchDaemons, sfltool
  11-sharing.sh            Sharing services, Bluetooth, profiles, Time Machine
  12-input.sh              Keyboard repeat, trackpad, accessibility
  13-appearance.sh         Dock, window management, wallpaper, focus
  14-apps.sh               /Applications listing, Homebrew Cellar/Caskroom, MAS
  15-homebrew.sh           brew leaves, list, casks, taps, Brewfile, deps
  16-shell-env.sh          $SHELL, $PATH, env vars (secrets redacted)
  17-dotfile-contents.sh   Copies key dotfiles to snapshot directory
  18-packages.sh           npm -g, pip3, gem, mise
  19-fonts.sh              User + system fonts
```

## Data flow

### Snapshot mode (default)

```
macstate.sh
  │
  ├─ mkdir -m 700 ~/MacSnapshots/<timestamp>/
  │
  ├─ For each collectors/NN-*.sh:
  │    ├─ parse_collector_header() → read LABEL, REQUIRES_SUDO
  │    ├─ should_run_collector()   → check --only/--skip filters
  │    ├─ source collector file    → load collect function
  │    └─ collect_name($OUTDIR, $DB)
  │         ├─ run_collect "label" "outfile" command...  → text output
  │         └─ (01-filesystem) python3 fs_index.py       → SQLite output
  │
  └─ Summary: entry count, collector count, total size
```

**Output directory structure:**
```
~/MacSnapshots/<timestamp>/
  filesystem.db              SQLite database (filesystem index)
  system_info.txt            System info
  defaults_NSGlobalDomain.txt
  defaults_domains/          Per-domain text exports
    com.apple.finder.txt
    com.apple.dock.txt
    ...
  individual_apps/           Key app domain exports
  network/                   Network config
  homebrew/                  Brew leaves, list, Brewfile, etc.
  dotfile_contents/          Copies of key dotfiles
    .zshrc
    .gitconfig
    .config/starship.toml
    ...
  security.txt
  power.txt
  shell_env.txt
  ...
```

### Diff mode (`--diff snap1 snap2`)

```
diff.sh: run_diff()
  │
  ├─ ATTACH both snapshot DBs
  ├─ Copy files tables → snap_a, snap_b (with optional --filter)
  ├─ Create SQL views:
  │    ├─ new_files         (in snap_b but not snap_a)
  │    ├─ deleted_files     (in snap_a but not snap_b)
  │    ├─ changed_files     (same path, different size/mtime/perms/owner)
  │    ├─ content_changes   (same path, different SHA-256)
  │    ├─ symlink_changes   (same path, different target)
  │    ├─ new_dotfiles      (dotfile content appeared)
  │    ├─ deleted_dotfiles  (dotfile content removed)
  │    └─ changed_dotfiles  (dotfile content SHA-256 differs)
  │
  ├─ Generate filesystem report → DIFF_*.txt
  │
  ├─ Text-diff all .txt/.plist files between snapshots
  │    └─ Append preference value changes → DIFF_*.txt
  │
  └─ Output: DIFF_*.db (queryable) + DIFF_*.txt (readable report)
```

### Query mode (`--query snap`)

Opens `filesystem.db` in interactive `sqlite3` shell. Useful for ad-hoc exploration.

### Export JSON mode (`--export-json snap`)

Combines SQLite metadata/files/dotfile_contents with all `.txt` collector files into a single JSON document.

## SQLite schema

```sql
-- Filesystem index
CREATE TABLE files (
    filepath        TEXT PRIMARY KEY,  -- Absolute path
    filetype        TEXT,              -- 'f' (file), 'd' (dir), 'l' (symlink)
    size            INTEGER,           -- Bytes
    modified        TEXT,              -- UTC ISO-8601: 2024-01-15T03:22:10Z
    permissions     TEXT,              -- Octal string: "755"
    owner           TEXT,              -- Username or UID
    grp             TEXT,              -- Group name or GID
    inode           INTEGER,
    symlink_target  TEXT,              -- Target path (NULL for non-symlinks)
    sha256          TEXT               -- SHA-256 hex (NULL if not hashed)
);

-- Snapshot metadata
CREATE TABLE metadata (
    key   TEXT PRIMARY KEY,  -- snapshot_time, macos_version, build, hostname, etc.
    value TEXT
);

-- Full text content of key dotfiles
CREATE TABLE dotfile_contents (
    filepath TEXT PRIMARY KEY,  -- Absolute path
    content  TEXT,              -- Full file content
    sha256   TEXT               -- SHA-256 of the file
);

-- Indexes
CREATE INDEX idx_files_modified ON files(modified);
CREATE INDEX idx_files_size ON files(size);
CREATE INDEX idx_files_type ON files(filetype);
CREATE INDEX idx_files_sha256 ON files(sha256);
```

## Collector module interface

Each collector file follows this contract:

```bash
# LABEL: Human-readable description     ← displayed during snapshot
# REQUIRES_SUDO: false                  ← skipped without sudo if true

collect_name() {                         ← function name derived from filename
    local outdir="$1"                    ← snapshot output directory
    local db="$2"                        ← path to filesystem.db

    # Use run_collect for simple command output:
    run_collect "label" "$outdir/file.txt" command args...

    # Or write directly for complex logic:
    mkdir -p "$outdir/subdir"
    some_command > "$outdir/subdir/output.txt" 2>/dev/null || true
}
```

**Function name derivation:** `collectors/03-defaults-domains.sh` → `collect_defaults_domains`
- Strip numeric prefix and `.sh` extension
- Replace hyphens with underscores
- Prepend `collect_`

**Helper naming:** Private helpers use `_col_` prefix (e.g., `_col_scutil` in `07-network.sh`) to avoid namespace collisions since all collectors are sourced into the same shell.

## Filesystem indexer internals

### What gets indexed

**Scan roots** (directories walked recursively):
- `$HOME/Library`, `$HOME/Applications`, `$HOME/.config`, `$HOME/.local`
- `$HOME/.ssh`, `$HOME/.gnupg`, `$HOME/.orbstack`
- `/Library`, `/Applications`, `/usr/local`, `/opt/homebrew`
- `/private/etc`, `/private/var/db/receipts`
- `/System/Library/LaunchDaemons`, `/System/Library/LaunchAgents`, `/System/Library/Extensions`

**Default excludes** (pruned from walk):
- `Library/Caches`, `Library/Logs`, `/Caches/`
- `node_modules`, `.git/objects`, `__pycache__`, `.Trash`

**Home dotfiles:** `$HOME/.*` scanned non-recursively (metadata only, not recursive into `~/.cache` etc.)

### What gets hashed (SHA-256)

Files are hashed when ALL of these are true:
- Size > 0 and < 1 MB
- File matches: config extension (`.plist`, `.toml`, `.yaml`, `.json`, `.conf`, `.cfg`, `.ini`) OR path contains `/.config/`, `/.ssh/`, `/.gnupg/`, `/Library/Preferences/`
- File is NOT a private key (`id_rsa`, `id_ed25519`, `.pem`, `.key`, etc.)
- File is NOT under `/private-keys-v1.d/`

### Dotfile content capture

Full text content stored in SQLite for a curated list of dotfiles (`.zshrc`, `.gitconfig`, `.ssh/config`, chezmoi config, starship config, etc.). Max 100 KB per file. This list is shared with `collectors/17-dotfile-contents.sh` which copies the same files to disk.

## Security model

The tool collects system state, which inherently includes some sensitive information. Mitigations:

| Risk | Mitigation |
|---|---|
| SSH/GPG private keys | Excluded from hashing by name/extension deny-list |
| Environment secrets | `env` output redacted for `*_TOKEN`, `*_SECRET`, `*_KEY`, `*_PASSWORD`, etc. |
| Snapshot readable by others | Output directory created with `chmod 700` |
| SQL injection via `--filter` | Whitelist regex: only `[a-zA-Z0-9_. /-]` allowed |
| Homebrew auto-update side effects | `HOMEBREW_NO_AUTO_UPDATE=1` set before brew commands |
| Commands that hang | `timeout` used on known-risky commands (e.g., `bputil`) |

**Known remaining exposure:** `chezmoi.toml` and `.ssh/config` are collected in full. If these contain tokens, they will be in the snapshot. The `dotfile_contents/` directory and SQLite table should be treated as sensitive.

## Adding a new collector

1. Create `collectors/NN-name.sh` (pick next number)
2. Add comment headers: `# LABEL:` and `# REQUIRES_SUDO:`
3. Define `collect_name()` function (hyphens → underscores)
4. Use `run_collect` for simple commands, or write files directly
5. Keep it read-only — never modify system state
6. Handle missing tools gracefully (`command -v ... || return 0`)
7. Test: `./macstate.sh --only name`

## Extending the diff

The diff engine automatically picks up new `.txt` and `.plist` files in snapshots for text comparison. For new SQLite-based data, add views to the SQL block in `lib/diff.sh`.
