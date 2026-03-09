"""Shared pytest fixtures for macstate tests."""

import sqlite3
from pathlib import Path

import pytest

PROJECT_DIR = Path(__file__).parent.parent


@pytest.fixture
def project_dir():
    return PROJECT_DIR


@pytest.fixture
def sample_tree(tmp_path):
    """Create a small directory tree for filesystem indexer tests."""
    # Regular files
    (tmp_path / "file.txt").write_text("hello")
    (tmp_path / "config.toml").write_text("[settings]\nkey = 'value'\n")
    (tmp_path / "data.json").write_text('{"a": 1}')

    # Subdirectory with files
    subdir = tmp_path / "subdir"
    subdir.mkdir()
    (subdir / "nested.plist").write_text("<plist>test</plist>")
    (subdir / "plain.log").write_text("log entry")

    # Symlink
    (tmp_path / "link.toml").symlink_to(tmp_path / "config.toml")

    # Excluded directory (should be pruned)
    node_modules = tmp_path / "node_modules"
    node_modules.mkdir()
    (node_modules / "package.json").write_text("{}")

    return tmp_path


@pytest.fixture
def sample_db(tmp_path):
    """Create an empty macstate SQLite database with correct schema."""
    import sys

    sys.path.insert(0, str(PROJECT_DIR / "lib"))
    from fs_index import create_schema

    db_path = tmp_path / "filesystem.db"
    db = sqlite3.connect(str(db_path), isolation_level=None)
    create_schema(db)
    yield db, db_path
    db.close()


@pytest.fixture
def sample_snapshot(tmp_path):
    """Create a minimal snapshot directory for export tests."""
    snap_dir = tmp_path / "snapshot"
    snap_dir.mkdir()

    # Create DB directly in the snapshot dir
    import sys

    sys.path.insert(0, str(PROJECT_DIR / "lib"))
    from fs_index import create_schema

    dest_db = snap_dir / "filesystem.db"
    conn = sqlite3.connect(str(dest_db), isolation_level=None)
    create_schema(conn)
    conn.execute("INSERT INTO metadata VALUES ('snapshot_time', '2024-01-15T10:00:00Z')")
    conn.execute("INSERT INTO metadata VALUES ('hostname', 'test-machine')")
    conn.execute(
        "INSERT INTO files VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            "/tmp/test.txt",
            "f",
            100,
            "2024-01-15T10:00:00Z",
            "644",
            "user",
            "staff",
            12345,
            None,
            None,
        ),
    )
    conn.execute(
        "INSERT INTO dotfile_contents VALUES (?, ?, ?)",
        ("/Users/test/.zshrc", "export PATH=$PATH:/usr/local/bin", "abc123"),
    )
    conn.close()

    # Add a text capture file
    (snap_dir / "system_info.txt").write_text("macOS 14.0\nDarwin Kernel\n")

    return snap_dir


@pytest.fixture
def sample_snapshot_pair(tmp_path):
    """Create two snapshot directories with deliberate differences for diff tests."""
    import sys

    sys.path.insert(0, str(PROJECT_DIR / "lib"))
    from fs_index import create_schema

    # Snapshot A (before)
    snap_a = tmp_path / "snap_a"
    snap_a.mkdir()
    db_a = sqlite3.connect(str(snap_a / "filesystem.db"), isolation_level=None)
    create_schema(db_a)
    db_a.execute("INSERT INTO metadata VALUES ('snapshot_time', '2024-01-15T10:00:00Z')")
    db_a.execute("INSERT INTO metadata VALUES ('hostname', 'test-machine')")
    db_a.execute(
        "INSERT INTO files VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ("/tmp/keep.txt", "f", 100, "2024-01-15T10:00:00Z", "644", "u", "s", 1, None, None),
    )
    db_a.execute(
        "INSERT INTO files VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ("/tmp/removed.txt", "f", 50, "2024-01-15T10:00:00Z", "644", "u", "s", 2, None, None),
    )
    db_a.execute(
        "INSERT INTO dotfile_contents VALUES (?, ?, ?)",
        ("/Users/test/.zshrc", "export OLD=1", "aaa"),
    )
    db_a.close()
    (snap_a / "system_info.txt").write_text("macOS 14.0\n")

    # Snapshot B (after)
    snap_b = tmp_path / "snap_b"
    snap_b.mkdir()
    db_b = sqlite3.connect(str(snap_b / "filesystem.db"), isolation_level=None)
    create_schema(db_b)
    db_b.execute("INSERT INTO metadata VALUES ('snapshot_time', '2024-01-16T10:00:00Z')")
    db_b.execute("INSERT INTO metadata VALUES ('hostname', 'test-machine')")
    db_b.execute(
        "INSERT INTO files VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ("/tmp/keep.txt", "f", 200, "2024-01-16T10:00:00Z", "644", "u", "s", 1, None, None),
    )
    db_b.execute(
        "INSERT INTO files VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ("/tmp/newfile.txt", "f", 75, "2024-01-16T10:00:00Z", "644", "u", "s", 3, None, None),
    )
    db_b.execute(
        "INSERT INTO dotfile_contents VALUES (?, ?, ?)",
        ("/Users/test/.zshrc", "export NEW=1", "bbb"),
    )
    db_b.close()
    (snap_b / "system_info.txt").write_text("macOS 14.1\n")

    return snap_a, snap_b
