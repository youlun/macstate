#!/usr/bin/env python3
"""Filesystem indexer for macstate.

Walks high-value directories and stores file metadata in SQLite.
Features:
  - SHA-256 hashes for high-value config files
  - Symlink target tracking
  - Dotfile content capture
  - Home directory dotfile scanning
"""

from __future__ import annotations

import argparse
import hashlib
import os
import pwd
import grp
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

SCHEMA_VERSION = "0.1"

# Files to hash (globs relative to any scan root)
HASH_EXTENSIONS = {".plist", ".toml", ".yaml", ".yml", ".json", ".conf", ".cfg", ".ini"}
HASH_PATHS_CONTAIN = {"/.config/", "/.ssh/", "/.gnupg/", "/Library/Preferences/"}
HASH_MAX_SIZE = 1 * 1024 * 1024  # 1MB

# Files to never hash (sensitive private key material)
HASH_EXCLUDE_NAMES = {
    "id_rsa", "id_ecdsa", "id_ed25519", "id_dsa", "id_xmss",
    "secring.gpg", "trustdb.gpg",
}
HASH_EXCLUDE_EXTENSIONS = {".pem", ".p12", ".pfx", ".key"}
HASH_EXCLUDE_PATHS = {"/private-keys-v1.d/"}

# Dotfiles whose full content we store
DOTFILE_CONTENT_LIST = [
    ".zshrc", ".zprofile", ".bashrc", ".bash_profile", ".gitconfig",
    ".ssh/config", ".config/chezmoi/chezmoi.toml",
    ".config/starship.toml", ".config/mise/config.toml",
    ".config/ghostty/config", ".config/git/ignore",
    ".config/homebrew/Brewfile",
    ".config/atuin/config.toml",
    ".config/bat/config",
    "Library/Application Support/lazygit/config.yml",
]
DOTFILE_MAX_SIZE = 100 * 1024  # 100KB


DEFAULT_EXCLUDES = [
    "Library/Caches",
    "Library/Logs",
    "/Caches/",
    "node_modules",
    ".git/objects",
    "__pycache__",
    ".Trash",
]


def get_default_scan_roots(home: str) -> list[str]:
    return [
        f"{home}/Library",
        f"{home}/Applications",
        f"{home}/.config",
        f"{home}/.local",
        f"{home}/.ssh",
        f"{home}/.gnupg",
        f"{home}/.orbstack",
        "/Library",
        "/Applications",
        "/usr/local",
        "/opt/homebrew",
        "/private/etc",
        "/private/var/db/receipts",
        "/System/Library/LaunchDaemons",
        "/System/Library/LaunchAgents",
        "/System/Library/Extensions",
    ]


def create_schema(db: sqlite3.Connection):
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    db.execute("""
        CREATE TABLE IF NOT EXISTS files (
            filepath        TEXT PRIMARY KEY,
            filetype        TEXT,
            size            INTEGER,
            modified        TEXT,
            permissions     TEXT,
            owner           TEXT,
            grp             TEXT,
            inode           INTEGER,
            symlink_target  TEXT,
            sha256          TEXT
        )
    """)
    db.execute("""
        CREATE TABLE IF NOT EXISTS metadata (
            key   TEXT PRIMARY KEY,
            value TEXT
        )
    """)
    db.execute("""
        CREATE TABLE IF NOT EXISTS dotfile_contents (
            filepath TEXT PRIMARY KEY,
            content  TEXT,
            sha256   TEXT
        )
    """)


def store_metadata(db: sqlite3.Connection):
    def cmd(args):
        try:
            return subprocess.check_output(args, stderr=subprocess.DEVNULL).decode().strip()
        except Exception:
            return "unknown"

    entries = [
        ("snapshot_time", datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")),
        ("macos_version", cmd(["sw_vers", "-productVersion"])),
        ("build", cmd(["sw_vers", "-buildVersion"])),
        ("hostname", cmd(["scutil", "--get", "ComputerName"])),
        ("username", os.environ.get("SUDO_USER", os.environ.get("USER", "unknown"))),
        ("schema_version", SCHEMA_VERSION),
    ]
    db.executemany("INSERT OR REPLACE INTO metadata VALUES (?, ?)", entries)


def should_hash(filepath: str, size: int) -> bool:
    if size > HASH_MAX_SIZE or size == 0:
        return False
    basename = os.path.basename(filepath)
    _, ext = os.path.splitext(filepath)
    # Never hash private key material
    if basename in HASH_EXCLUDE_NAMES or ext.lower() in HASH_EXCLUDE_EXTENSIONS:
        return False
    if any(p in filepath for p in HASH_EXCLUDE_PATHS):
        return False
    if ext.lower() in HASH_EXTENSIONS:
        return True
    return any(p in filepath for p in HASH_PATHS_CONTAIN)


def hash_file(filepath: str) -> str | None:
    try:
        h = hashlib.sha256()
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                h.update(chunk)
        return h.hexdigest()
    except (OSError, PermissionError):
        return None


def get_owner(uid: int) -> str:
    try:
        return pwd.getpwuid(uid).pw_name
    except KeyError:
        return str(uid)


def get_group(gid: int) -> str:
    try:
        return grp.getgrgid(gid).gr_name
    except KeyError:
        return str(gid)


def scan_entry(path: str) -> tuple | None:
    """Returns a tuple for the files table, or None on error."""
    try:
        s = os.lstat(path)
    except (OSError, PermissionError):
        return None

    import stat
    if stat.S_ISREG(s.st_mode):
        ftype = "f"
    elif stat.S_ISDIR(s.st_mode):
        ftype = "d"
    elif stat.S_ISLNK(s.st_mode):
        ftype = "l"
    else:
        return None

    symlink_target = None
    if ftype == "l":
        try:
            symlink_target = os.readlink(path)
        except OSError:
            pass

    sha = None
    if ftype == "f" and should_hash(path, s.st_size):
        sha = hash_file(path)

    return (
        path,
        ftype,
        s.st_size,
        datetime.fromtimestamp(s.st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        format(stat.S_IMODE(s.st_mode), "o"),
        get_owner(s.st_uid),
        get_group(s.st_gid),
        s.st_ino,
        symlink_target,
        sha,
    )


def scan_directory(root: str, db: sqlite3.Connection, count: list, errors: list,
                   exclude_patterns: list[str]):
    """Walk a directory tree and insert entries into the database."""
    batch = []
    batch_size = 5000

    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        # Prune excluded patterns
        if any(p in dirpath for p in exclude_patterns):
            dirnames.clear()
            continue

        # Scan the directory itself
        entry = scan_entry(dirpath)
        if entry:
            batch.append(entry)

        # Scan files and symlinks
        for name in filenames:
            filepath = os.path.join(dirpath, name)
            entry = scan_entry(filepath)
            if entry:
                batch.append(entry)
            else:
                errors[0] += 1

        # Scan symlinks in dirnames (os.walk doesn't follow them)
        for name in dirnames:
            filepath = os.path.join(dirpath, name)
            if os.path.islink(filepath):
                entry = scan_entry(filepath)
                if entry:
                    batch.append(entry)
                else:
                    errors[0] += 1

        if len(batch) >= batch_size:
            db.executemany(
                "INSERT OR REPLACE INTO files VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                batch,
            )
            count[0] += len(batch)
            batch.clear()
            if count[0] % 25000 < batch_size:
                print(f"  -> {count[0]} entries scanned...", file=sys.stderr)

    # Flush remaining
    if batch:
        db.executemany(
            "INSERT OR REPLACE INTO files VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            batch,
        )
        count[0] += len(batch)


def scan_home_dotfiles(home: str, db: sqlite3.Connection, count: list):
    """Scan individual dotfiles in $HOME (non-recursive)."""
    batch = []
    try:
        for item in os.scandir(home):
            if item.name.startswith(".") and not item.name.startswith(".."):
                entry = scan_entry(item.path)
                if entry:
                    batch.append(entry)
    except PermissionError:
        pass

    if batch:
        db.executemany(
            "INSERT OR REPLACE INTO files VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            batch,
        )
        count[0] += len(batch)


def collect_dotfile_contents(home: str, db: sqlite3.Connection):
    """Store full contents of key dotfiles."""
    for relpath in DOTFILE_CONTENT_LIST:
        filepath = os.path.join(home, relpath)
        if not os.path.isfile(filepath):
            continue
        try:
            size = os.path.getsize(filepath)
            if size > DOTFILE_MAX_SIZE:
                continue
            with open(filepath, "r", errors="replace") as f:
                content = f.read()
            sha = hash_file(filepath) or ""
            db.execute(
                "INSERT OR REPLACE INTO dotfile_contents VALUES (?, ?, ?)",
                (filepath, content, sha),
            )
        except (OSError, PermissionError):
            continue


def main():
    parser = argparse.ArgumentParser(description="macOS filesystem indexer")
    parser.add_argument("--db", required=True, help="Output SQLite database path")
    parser.add_argument("--home", required=True, help="Real user home directory")
    parser.add_argument("--scan-roots", help="File with additional scan roots (one per line)")
    parser.add_argument("--exclude", action="append", default=[], help="Exclude patterns")
    parser.add_argument("--no-system", action="store_true", help="Skip /System/Library")
    args = parser.parse_args()

    home = args.home
    db = sqlite3.connect(args.db, isolation_level=None)
    create_schema(db)

    scan_roots = get_default_scan_roots(home)

    if args.scan_roots and os.path.isfile(args.scan_roots):
        with open(args.scan_roots) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    scan_roots.append(line)

    if args.no_system:
        scan_roots = [r for r in scan_roots if not r.startswith("/System")]

    # Filter to existing directories
    scan_roots = [r for r in scan_roots if os.path.isdir(r)]

    # Default excludes (caches, logs, build artifacts)
    exclude_patterns = list(DEFAULT_EXCLUDES) + list(args.exclude)

    count = [0]
    errors = [0]
    start = time.time()

    db.execute("BEGIN TRANSACTION")
    try:
        store_metadata(db)

        # Scan home dotfiles first (non-recursive)
        scan_home_dotfiles(home, db, count)

        # Scan each root
        for root in scan_roots:
            scan_directory(root, db, count, errors, exclude_patterns)

        # Capture dotfile contents
        collect_dotfile_contents(home, db)

        # Create indexes inside the transaction
        db.execute("CREATE INDEX IF NOT EXISTS idx_files_modified ON files(modified)")
        db.execute("CREATE INDEX IF NOT EXISTS idx_files_size ON files(size)")
        db.execute("CREATE INDEX IF NOT EXISTS idx_files_type ON files(filetype)")
        db.execute("CREATE INDEX IF NOT EXISTS idx_files_sha256 ON files(sha256)")

        db.execute("COMMIT")
    except BaseException:
        try:
            db.execute("ROLLBACK")
        except Exception:
            pass
        db.close()
        # Remove partial DB so caller doesn't mistake it for a valid snapshot
        try:
            os.remove(args.db)
        except OSError:
            pass
        raise

    elapsed = time.time() - start
    print(
        f"  -> Done: {count[0]} entries indexed, {errors[0]} errors skipped ({elapsed:.1f}s)",
        file=sys.stderr,
    )

    db.close()


if __name__ == "__main__":
    main()
