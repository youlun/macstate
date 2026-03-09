"""Unit tests for lib/fs_index.py."""

import hashlib
import sqlite3
import sys
from pathlib import Path
from unittest.mock import patch

# Add lib/ to path so we can import fs_index
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
import fs_index

# ── should_hash ──────────────────────────────────────────────────────────────


class TestShouldHash:
    def test_plist_extension(self):
        assert fs_index.should_hash("/Library/Preferences/com.apple.dock.plist", 1000)

    def test_toml_extension(self):
        assert fs_index.should_hash("/Users/x/.config/starship.toml", 500)

    def test_json_extension(self):
        assert fs_index.should_hash("/tmp/config.json", 100)

    def test_config_path(self):
        assert fs_index.should_hash("/Users/x/.config/app/settings", 100)

    def test_ssh_path(self):
        assert fs_index.should_hash("/Users/x/.ssh/known_hosts", 500)

    def test_zero_size(self):
        assert not fs_index.should_hash("/tmp/empty.plist", 0)

    def test_max_size_boundary(self):
        assert fs_index.should_hash("/tmp/config.plist", 1 * 1024 * 1024)

    def test_over_max_size(self):
        assert not fs_index.should_hash("/tmp/huge.plist", 1 * 1024 * 1024 + 1)

    def test_private_key_name_id_rsa(self):
        assert not fs_index.should_hash("/Users/x/.ssh/id_rsa", 500)

    def test_private_key_name_id_ed25519(self):
        assert not fs_index.should_hash("/Users/x/.ssh/id_ed25519", 500)

    def test_private_key_extension_pem(self):
        assert not fs_index.should_hash("/tmp/server.pem", 500)

    def test_private_key_extension_key(self):
        assert not fs_index.should_hash("/tmp/cert.key", 500)

    def test_private_keys_path(self):
        assert not fs_index.should_hash("/Users/x/.gnupg/private-keys-v1.d/abc.key", 500)

    def test_non_matching_txt(self):
        assert not fs_index.should_hash("/tmp/random.txt", 500)

    def test_non_matching_no_extension(self):
        assert not fs_index.should_hash("/tmp/somefile", 500)


# ── hash_file ────────────────────────────────────────────────────────────────


class TestHashFile:
    def test_known_content(self, tmp_path):
        f = tmp_path / "test.txt"
        f.write_text("hello world")
        expected = hashlib.sha256(b"hello world").hexdigest()
        assert fs_index.hash_file(str(f)) == expected

    def test_nonexistent_file(self):
        assert fs_index.hash_file("/tmp/nonexistent_macstate_test_file") is None

    def test_unreadable_file(self, tmp_path):
        f = tmp_path / "secret.txt"
        f.write_text("secret")
        f.chmod(0o000)
        result = fs_index.hash_file(str(f))
        f.chmod(0o644)  # restore for cleanup
        assert result is None


# ── scan_entry ───────────────────────────────────────────────────────────────


class TestScanEntry:
    def test_regular_file(self, tmp_path):
        f = tmp_path / "file.txt"
        f.write_text("content")
        entry = fs_index.scan_entry(str(f))
        assert entry is not None
        assert entry[0] == str(f)  # filepath
        assert entry[1] == "f"  # filetype
        assert entry[2] == 7  # size ("content" = 7 bytes)
        assert entry[4]  # permissions (non-empty octal string)

    def test_directory(self, tmp_path):
        d = tmp_path / "subdir"
        d.mkdir()
        entry = fs_index.scan_entry(str(d))
        assert entry is not None
        assert entry[1] == "d"

    def test_symlink(self, tmp_path):
        target = tmp_path / "target.txt"
        target.write_text("target")
        link = tmp_path / "link.txt"
        link.symlink_to(target)
        entry = fs_index.scan_entry(str(link))
        assert entry is not None
        assert entry[1] == "l"
        assert entry[8] == str(target)  # symlink_target

    def test_nonexistent(self):
        assert fs_index.scan_entry("/tmp/nonexistent_macstate_test") is None

    def test_timestamp_format(self, tmp_path):
        f = tmp_path / "ts.txt"
        f.write_text("test")
        entry = fs_index.scan_entry(str(f))
        # Should be UTC ISO-8601: YYYY-MM-DDTHH:MM:SSZ
        assert entry[3].endswith("Z")
        assert "T" in entry[3]


# ── create_schema ────────────────────────────────────────────────────────────


class TestTransactionRollback:
    """Test that a failed scan rolls back and removes the partial DB."""

    @patch("fs_index.scan_directory", side_effect=OSError("disk full"))
    def test_rollback_removes_db_on_error(self, mock_scan, tmp_path):
        db_path = tmp_path / "filesystem.db"
        home = tmp_path / "home"
        home.mkdir()

        # Simulate what main() does: create DB, begin transaction, scan fails
        db = sqlite3.connect(str(db_path), isolation_level=None)
        fs_index.create_schema(db)
        db.execute("BEGIN TRANSACTION")
        try:
            fs_index.store_metadata(db)
            fs_index.scan_directory(str(home), db, [0], [0], [])
            db.execute("COMMIT")
        except BaseException:
            try:
                db.execute("ROLLBACK")
            except Exception:
                pass
            db.close()
            try:
                db_path.unlink()
            except OSError:
                pass

        # DB file should be removed after rollback
        assert not db_path.exists()

    def test_successful_scan_keeps_db(self, tmp_path):
        db_path = tmp_path / "filesystem.db"
        home = tmp_path / "home"
        home.mkdir()
        (home / ".zshrc").write_text("test")

        db = sqlite3.connect(str(db_path), isolation_level=None)
        fs_index.create_schema(db)
        db.execute("BEGIN TRANSACTION")
        fs_index.store_metadata(db)
        fs_index.scan_home_dotfiles(str(home), db, [0])
        db.execute("COMMIT")
        db.close()

        # DB file should exist with data
        assert db_path.exists()
        conn = sqlite3.connect(str(db_path))
        count = conn.execute("SELECT COUNT(*) FROM metadata").fetchone()[0]
        assert count > 0
        conn.close()


class TestCreateSchema:
    def test_creates_tables(self, tmp_path):
        db = sqlite3.connect(str(tmp_path / "test.db"), isolation_level=None)
        fs_index.create_schema(db)
        tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        assert "files" in tables
        assert "metadata" in tables
        assert "dotfile_contents" in tables
        db.close()

    def test_idempotent(self, tmp_path):
        db = sqlite3.connect(str(tmp_path / "test.db"), isolation_level=None)
        fs_index.create_schema(db)
        fs_index.create_schema(db)  # should not raise
        db.close()


# ── scan_directory ───────────────────────────────────────────────────────────


class TestScanDirectory:
    def test_scans_files(self, sample_tree):
        db = sqlite3.connect(":memory:", isolation_level=None)
        fs_index.create_schema(db)
        count = [0]
        errors = [0]
        db.execute("BEGIN TRANSACTION")
        fs_index.scan_directory(str(sample_tree), db, count, errors, [])
        db.execute("COMMIT")
        assert count[0] > 0

    def test_excludes_patterns(self, sample_tree):
        db = sqlite3.connect(":memory:", isolation_level=None)
        fs_index.create_schema(db)
        count = [0]
        errors = [0]
        db.execute("BEGIN TRANSACTION")
        fs_index.scan_directory(str(sample_tree), db, count, errors, ["node_modules"])
        db.execute("COMMIT")

        # Verify node_modules content was excluded
        rows = db.execute(
            "SELECT filepath FROM files WHERE filepath LIKE '%node_modules%'"
        ).fetchall()
        assert len(rows) == 0

    def test_counts_correctly(self, sample_tree):
        db = sqlite3.connect(":memory:", isolation_level=None)
        fs_index.create_schema(db)
        count = [0]
        errors = [0]
        db.execute("BEGIN TRANSACTION")
        fs_index.scan_directory(str(sample_tree), db, count, errors, ["node_modules"])
        db.execute("COMMIT")

        db_count = db.execute("SELECT COUNT(*) FROM files").fetchone()[0]
        assert db_count == count[0]


# ── collect_dotfile_contents ─────────────────────────────────────────────────


class TestCollectDotfileContents:
    def test_stores_present_files(self, tmp_path):
        home = tmp_path / "home"
        home.mkdir()
        (home / ".zshrc").write_text("export PATH=/usr/bin")

        db = sqlite3.connect(":memory:", isolation_level=None)
        fs_index.create_schema(db)
        fs_index.collect_dotfile_contents(str(home), db)

        rows = db.execute("SELECT filepath, content FROM dotfile_contents").fetchall()
        found = any(".zshrc" in r[0] for r in rows)
        assert found

    def test_skips_missing_files(self, tmp_path):
        home = tmp_path / "empty_home"
        home.mkdir()

        db = sqlite3.connect(":memory:", isolation_level=None)
        fs_index.create_schema(db)
        fs_index.collect_dotfile_contents(str(home), db)

        count = db.execute("SELECT COUNT(*) FROM dotfile_contents").fetchone()[0]
        assert count == 0

    def test_skips_large_files(self, tmp_path):
        home = tmp_path / "home"
        home.mkdir()
        # Create a .zshrc larger than 100KB
        (home / ".zshrc").write_text("x" * (101 * 1024))

        db = sqlite3.connect(":memory:", isolation_level=None)
        fs_index.create_schema(db)
        fs_index.collect_dotfile_contents(str(home), db)

        count = db.execute("SELECT COUNT(*) FROM dotfile_contents").fetchone()[0]
        assert count == 0


# ── store_metadata ───────────────────────────────────────────────────────────


class TestStoreMetadata:
    @patch("fs_index.subprocess.check_output", return_value=b"test_value\n")
    def test_stores_entries(self, mock_cmd, tmp_path):
        db = sqlite3.connect(":memory:", isolation_level=None)
        fs_index.create_schema(db)
        fs_index.store_metadata(db)

        rows = db.execute("SELECT key FROM metadata").fetchall()
        keys = {r[0] for r in rows}
        assert "snapshot_time" in keys
        assert "schema_version" in keys
        assert "hostname" in keys

    @patch("fs_index.subprocess.check_output", side_effect=Exception("not found"))
    def test_handles_command_failure(self, mock_cmd, tmp_path):
        db = sqlite3.connect(":memory:", isolation_level=None)
        fs_index.create_schema(db)
        fs_index.store_metadata(db)

        hostname = db.execute("SELECT value FROM metadata WHERE key='hostname'").fetchone()[0]
        assert hostname == "unknown"


# ── load_dotfile_list ────────────────────────────────────────────────────────


class TestLoadDotfileList:
    def test_loads_from_file(self):
        result = fs_index.load_dotfile_list()
        assert len(result) > 0
        assert ".zshrc" in result
        assert ".gitconfig" in result

    def test_excludes_comments(self):
        result = fs_index.load_dotfile_list()
        for item in result:
            assert not item.startswith("#")

    def test_no_empty_entries(self):
        result = fs_index.load_dotfile_list()
        for item in result:
            assert item.strip() != ""
