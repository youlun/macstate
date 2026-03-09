#!/usr/bin/env python3
"""Export a macOS snapshot to JSON format."""

import json
import sqlite3
import sys
from pathlib import Path


def export_snapshot(snapshot_dir: str, output_path: str | None = None):
    snapshot_dir = Path(snapshot_dir)
    db_path = snapshot_dir / "filesystem.db"

    result: dict = {
        "snapshot_dir": str(snapshot_dir),
        "metadata": {},
        "files": {"total": 0, "by_type": {}},
        "dotfile_contents": {},
        "captures": {},
    }

    # Extract metadata and file stats from SQLite
    if db_path.exists():
        db = sqlite3.connect(str(db_path))
        db.row_factory = sqlite3.Row

        for row in db.execute("SELECT key, value FROM metadata"):
            result["metadata"][row["key"]] = row["value"]

        result["files"]["total"] = db.execute("SELECT COUNT(*) FROM files").fetchone()[0]
        for row in db.execute("SELECT filetype, COUNT(*) as cnt FROM files GROUP BY filetype"):
            result["files"]["by_type"][row["filetype"]] = row["cnt"]

        # Dotfile contents
        try:
            for row in db.execute("SELECT filepath, content, sha256 FROM dotfile_contents"):
                result["dotfile_contents"][row["filepath"]] = {
                    "sha256": row["sha256"],
                    "content": row["content"],
                }
        except sqlite3.OperationalError:
            pass  # Table doesn't exist in older snapshots

        db.close()

    # Capture text files
    for txt_file in sorted(snapshot_dir.rglob("*.txt")):
        rel = str(txt_file.relative_to(snapshot_dir))
        try:
            result["captures"][rel] = txt_file.read_text(errors="replace")
        except OSError:
            pass

    # Output
    output = output_path or str(snapshot_dir / "snapshot.json")
    with open(output, "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"Exported to {output}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <snapshot_dir> [output.json]", file=sys.stderr)
        sys.exit(1)
    export_snapshot(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
