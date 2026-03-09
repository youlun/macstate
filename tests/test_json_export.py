"""Unit tests for lib/json_export.py."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from json_export import export_snapshot


class TestExportSnapshot:
    def test_valid_json_output(self, sample_snapshot, tmp_path):
        output = str(tmp_path / "output.json")
        export_snapshot(str(sample_snapshot), output)

        with open(output) as f:
            data = json.load(f)

        assert "metadata" in data
        assert "files" in data
        assert "dotfile_contents" in data
        assert "captures" in data

    def test_metadata_populated(self, sample_snapshot, tmp_path):
        output = str(tmp_path / "output.json")
        export_snapshot(str(sample_snapshot), output)

        with open(output) as f:
            data = json.load(f)

        assert data["metadata"]["hostname"] == "test-machine"
        assert data["metadata"]["snapshot_time"] == "2024-01-15T10:00:00Z"

    def test_file_count(self, sample_snapshot, tmp_path):
        output = str(tmp_path / "output.json")
        export_snapshot(str(sample_snapshot), output)

        with open(output) as f:
            data = json.load(f)

        assert data["files"]["total"] == 1

    def test_dotfile_contents_populated(self, sample_snapshot, tmp_path):
        output = str(tmp_path / "output.json")
        export_snapshot(str(sample_snapshot), output)

        with open(output) as f:
            data = json.load(f)

        assert len(data["dotfile_contents"]) == 1

    def test_text_captures(self, sample_snapshot, tmp_path):
        output = str(tmp_path / "output.json")
        export_snapshot(str(sample_snapshot), output)

        with open(output) as f:
            data = json.load(f)

        assert "system_info.txt" in data["captures"]
        assert "macOS 14.0" in data["captures"]["system_info.txt"]

    def test_missing_db_graceful(self, tmp_path):
        """Snapshot directory without filesystem.db should still export."""
        snap = tmp_path / "no_db_snap"
        snap.mkdir()
        (snap / "info.txt").write_text("some info")

        output = str(tmp_path / "output.json")
        export_snapshot(str(snap), output)

        with open(output) as f:
            data = json.load(f)

        assert data["files"]["total"] == 0
        assert data["metadata"] == {}
        assert "info.txt" in data["captures"]

    def test_default_output_path(self, sample_snapshot):
        """Without explicit output, writes snapshot.json in snapshot dir."""
        export_snapshot(str(sample_snapshot))
        assert (sample_snapshot / "snapshot.json").exists()
