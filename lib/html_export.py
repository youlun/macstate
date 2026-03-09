#!/usr/bin/env python3
"""Export a macOS snapshot (or diff of two) as a self-contained HTML viewer."""

from __future__ import annotations

import difflib
import json
import sqlite3
import sys
from pathlib import Path


def _load_snapshot(snapshot_dir: Path) -> dict:
    """Read metadata, file stats, dotfile contents, and text captures from a snapshot."""
    data: dict = {
        "snapshot_dir": str(snapshot_dir),
        "metadata": {},
        "files": {"total": 0, "by_type": {}},
        "dotfile_contents": {},
        "captures": {},
    }

    db_path = snapshot_dir / "filesystem.db"
    if db_path.exists():
        db = sqlite3.connect(str(db_path))
        db.row_factory = sqlite3.Row

        for row in db.execute("SELECT key, value FROM metadata"):
            data["metadata"][row["key"]] = row["value"]

        data["files"]["total"] = db.execute("SELECT COUNT(*) FROM files").fetchone()[0]
        for row in db.execute("SELECT filetype, COUNT(*) as cnt FROM files GROUP BY filetype"):
            data["files"]["by_type"][row["filetype"]] = row["cnt"]

        try:
            for row in db.execute("SELECT filepath, content, sha256 FROM dotfile_contents"):
                data["dotfile_contents"][row["filepath"]] = {
                    "sha256": row["sha256"],
                    "content": row["content"],
                }
        except sqlite3.OperationalError:
            pass

        db.close()

    for txt_file in sorted(snapshot_dir.rglob("*.txt")):
        rel = str(txt_file.relative_to(snapshot_dir))
        try:
            data["captures"][rel] = txt_file.read_text(errors="replace")
        except OSError:
            pass

    return data


def _run_sql_diff(db1: Path, db2: Path) -> dict:
    """Run diff SQL views on two filesystem.db files, return structured data."""
    for p in (db1, db2):
        if "'" in str(p):
            raise ValueError(f"Snapshot path contains unsafe characters: {p}")

    db = sqlite3.connect(":memory:")
    db.row_factory = sqlite3.Row

    db.execute(f"ATTACH DATABASE '{db1}' AS before_snap")
    db.execute(f"ATTACH DATABASE '{db2}' AS after_snap")

    db.execute("CREATE TABLE snap_a AS SELECT * FROM before_snap.files")
    db.execute("CREATE TABLE snap_b AS SELECT * FROM after_snap.files")
    db.execute("CREATE INDEX idx_a_path ON snap_a(filepath)")
    db.execute("CREATE INDEX idx_b_path ON snap_b(filepath)")

    db.execute("CREATE TABLE meta_a AS SELECT * FROM before_snap.metadata")
    db.execute("CREATE TABLE meta_b AS SELECT * FROM after_snap.metadata")

    # Views — mirroring lib/diff.sh
    db.execute("""
        CREATE VIEW new_files AS
        SELECT b.* FROM snap_b b
        LEFT JOIN snap_a a ON b.filepath = a.filepath
        WHERE a.filepath IS NULL
    """)
    db.execute("""
        CREATE VIEW deleted_files AS
        SELECT a.* FROM snap_a a
        LEFT JOIN snap_b b ON a.filepath = b.filepath
        WHERE b.filepath IS NULL
    """)
    db.execute("""
        CREATE VIEW changed_files AS
        SELECT
            a.filepath,
            a.size AS old_size, b.size AS new_size,
            a.modified AS old_modified, b.modified AS new_modified,
            a.permissions AS old_perms, b.permissions AS new_perms,
            a.owner AS old_owner, b.owner AS new_owner
        FROM snap_a a
        JOIN snap_b b ON a.filepath = b.filepath
        WHERE a.size != b.size
           OR a.modified != b.modified
           OR a.permissions != b.permissions
           OR a.owner != b.owner
    """)
    db.execute("""
        CREATE VIEW content_changes AS
        SELECT
            a.filepath,
            a.size AS old_size, b.size AS new_size,
            a.sha256 AS old_sha256, b.sha256 AS new_sha256
        FROM snap_a a
        JOIN snap_b b ON a.filepath = b.filepath
        WHERE a.sha256 IS NOT NULL AND b.sha256 IS NOT NULL
          AND a.sha256 != b.sha256
    """)
    db.execute("""
        CREATE VIEW symlink_changes AS
        SELECT
            a.filepath,
            a.symlink_target AS old_target,
            b.symlink_target AS new_target
        FROM snap_a a
        JOIN snap_b b ON a.filepath = b.filepath
        WHERE a.filetype = 'l' AND b.filetype = 'l'
          AND COALESCE(a.symlink_target, '') != COALESCE(b.symlink_target, '')
    """)

    def rows_to_dicts(query: str) -> list[dict]:
        return [dict(r) for r in db.execute(query).fetchall()]

    summary_row = db.execute("""
        SELECT
            (SELECT COUNT(*) FROM new_files) AS new_files,
            (SELECT COUNT(*) FROM deleted_files) AS deleted_files,
            (SELECT COUNT(*) FROM changed_files) AS changed_files,
            (SELECT COUNT(*) FROM content_changes) AS content_changes,
            (SELECT COUNT(*) FROM symlink_changes) AS symlink_changes,
            (SELECT COUNT(*) FROM snap_a) AS total_before,
            (SELECT COUNT(*) FROM snap_b) AS total_after
    """).fetchone()

    result = {
        "meta_a": dict(db.execute("SELECT key, value FROM meta_a").fetchall()),
        "meta_b": dict(db.execute("SELECT key, value FROM meta_b").fetchall()),
        "summary": dict(summary_row),
        "new_files": rows_to_dicts(
            "SELECT filepath, filetype, size, modified"
            " FROM new_files ORDER BY modified DESC LIMIT 500"
        ),
        "deleted_files": rows_to_dicts(
            "SELECT filepath, filetype, size FROM deleted_files ORDER BY filepath LIMIT 500"
        ),
        "changed_files": rows_to_dicts(
            "SELECT filepath, old_size, new_size,"
            " old_modified, new_modified, old_perms, new_perms"
            " FROM changed_files ORDER BY new_modified DESC LIMIT 500"
        ),
        "content_changes": rows_to_dicts(
            "SELECT filepath, old_size, new_size FROM content_changes LIMIT 500"
        ),
        "symlink_changes": rows_to_dicts(
            "SELECT filepath, old_target, new_target FROM symlink_changes LIMIT 200"
        ),
    }

    db.execute("DETACH DATABASE before_snap")
    db.execute("DETACH DATABASE after_snap")
    db.close()

    return result


def _compute_text_diffs(snap1_dir: Path, snap2_dir: Path) -> list[dict]:
    """Compute unified diffs of .txt/.plist files between two snapshots."""
    extensions = {"*.txt", "*.plist"}
    files1: set[str] = set()
    files2: set[str] = set()

    for ext in extensions:
        for f in snap1_dir.rglob(ext):
            rel = str(f.relative_to(snap1_dir))
            if "DIFF" not in rel and "filesystem.db" not in rel:
                files1.add(rel)
        for f in snap2_dir.rglob(ext):
            rel = str(f.relative_to(snap2_dir))
            if "DIFF" not in rel and "filesystem.db" not in rel:
                files2.add(rel)

    all_files = sorted(files1 | files2)
    diffs: list[dict] = []

    for rel in all_files:
        f1 = snap1_dir / rel
        f2 = snap2_dir / rel

        if not f1.exists():
            diffs.append({"path": rel, "status": "new", "diff": ""})
        elif not f2.exists():
            diffs.append({"path": rel, "status": "removed", "diff": ""})
        else:
            try:
                lines1 = f1.read_text(errors="replace").splitlines(keepends=True)
                lines2 = f2.read_text(errors="replace").splitlines(keepends=True)
            except OSError:
                continue
            diff_lines = list(
                difflib.unified_diff(
                    lines1,
                    lines2,
                    fromfile=f"before/{rel}",
                    tofile=f"after/{rel}",
                    lineterm="",
                )
            )
            if diff_lines:
                diffs.append(
                    {
                        "path": rel,
                        "status": "changed",
                        "diff": "\n".join(diff_lines),
                    }
                )

    return diffs


def _compute_dotfile_diffs(db1: Path, db2: Path) -> list[dict]:
    """Compute diffs of dotfile contents between two snapshots."""

    def read_dotfiles(db_path: Path) -> dict[str, str]:
        if not db_path.exists():
            return {}
        db = sqlite3.connect(str(db_path))
        try:
            rows = db.execute("SELECT filepath, content FROM dotfile_contents").fetchall()
            return {r[0]: r[1] for r in rows}
        except sqlite3.OperationalError:
            return {}
        finally:
            db.close()

    before = read_dotfiles(db1)
    after = read_dotfiles(db2)
    all_paths = sorted(set(before) | set(after))
    diffs: list[dict] = []

    for path in all_paths:
        if path not in before:
            diffs.append(
                {
                    "filepath": path,
                    "status": "new",
                    "diff": "",
                    "content": after[path],
                }
            )
        elif path not in after:
            diffs.append(
                {
                    "filepath": path,
                    "status": "removed",
                    "diff": "",
                    "content": before[path],
                }
            )
        elif before[path] != after[path]:
            diff_lines = list(
                difflib.unified_diff(
                    before[path].splitlines(keepends=True),
                    after[path].splitlines(keepends=True),
                    fromfile=f"before: {path}",
                    tofile=f"after: {path}",
                    lineterm="",
                )
            )
            diffs.append(
                {
                    "filepath": path,
                    "status": "changed",
                    "diff": "\n".join(diff_lines),
                }
            )

    return diffs


def _load_template() -> str:
    """Read the HTML template from lib/viewer_template.html."""
    template_path = Path(__file__).parent / "viewer_template.html"
    return template_path.read_text()


def _inject_payload(template: str, payload: dict) -> str:
    """Inject JSON payload into the HTML template."""
    payload_json = json.dumps(payload, ensure_ascii=False)
    # Prevent breaking out of <script> tag (covers all case variants)
    payload_json = payload_json.replace("</", r"<\/")
    return template.replace(
        "/* __MACSTATE_DATA__ */",
        f"const DATA = {payload_json};",
    )


def export_html(
    snapshot_dir: str,
    snap2_dir: str | None = None,
    output_path: str | None = None,
) -> str:
    """Generate a self-contained HTML viewer for a snapshot or diff."""
    snap1 = Path(snapshot_dir)
    template = _load_template()

    if snap2_dir:
        snap2 = Path(snap2_dir)
        db1 = snap1 / "filesystem.db"
        db2 = snap2 / "filesystem.db"

        if not db1.exists() or not db2.exists():
            print(
                "Error: both snapshots must contain filesystem.db",
                file=sys.stderr,
            )
            sys.exit(1)

        sql_diff = _run_sql_diff(db1, db2)
        pref_diffs = _compute_text_diffs(snap1, snap2)
        dotfile_diffs = _compute_dotfile_diffs(db1, db2)

        payload = {
            "mode": "diff",
            "snap_a": _load_snapshot(snap1),
            "snap_b": _load_snapshot(snap2),
            "sql_diff": sql_diff,
            "pref_diffs": pref_diffs,
            "dotfile_diffs": dotfile_diffs,
        }

        if not output_path:
            diffs_dir = snap1.parent / "diffs"
            diffs_dir.mkdir(mode=0o700, exist_ok=True)
            output_path = str(diffs_dir / f"DIFF_{snap1.name}_vs_{snap2.name}.html")
    else:
        payload = {
            "mode": "single",
            "snapshot": _load_snapshot(snap1),
        }
        if not output_path:
            output_path = str(snap1 / "snapshot.html")

    html = _inject_payload(template, payload)
    Path(output_path).write_text(html)
    print(f"Exported to {output_path}")
    return output_path


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(
            f"Usage: {sys.argv[0]} <snapshot_dir> [snapshot_dir2]",
            file=sys.stderr,
        )
        sys.exit(1)
    export_html(
        sys.argv[1],
        sys.argv[2] if len(sys.argv) > 2 else None,
    )
