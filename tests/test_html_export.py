"""Unit tests for lib/html_export.py."""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from html_export import export_html


class TestExportHtmlSingle:
    def test_creates_html_file(self, sample_snapshot, tmp_path):
        output = str(tmp_path / "output.html")
        export_html(str(sample_snapshot), output_path=output)
        assert Path(output).exists()

    def test_valid_html_structure(self, sample_snapshot, tmp_path):
        output = str(tmp_path / "output.html")
        export_html(str(sample_snapshot), output_path=output)
        content = Path(output).read_text()
        assert "<!DOCTYPE html>" in content
        assert "</html>" in content
        assert "const DATA =" in content

    def test_metadata_in_output(self, sample_snapshot, tmp_path):
        output = str(tmp_path / "output.html")
        export_html(str(sample_snapshot), output_path=output)
        content = Path(output).read_text()
        assert "test-machine" in content
        assert "2024-01-15T10:00:00Z" in content

    def test_captures_in_output(self, sample_snapshot, tmp_path):
        output = str(tmp_path / "output.html")
        export_html(str(sample_snapshot), output_path=output)
        content = Path(output).read_text()
        assert "macOS 14.0" in content

    def test_embedded_json_parseable(self, sample_snapshot, tmp_path):
        output = str(tmp_path / "output.html")
        export_html(str(sample_snapshot), output_path=output)
        content = Path(output).read_text()
        match = re.search(r"const DATA = ({.*?});\s*\n", content, re.DOTALL)
        assert match is not None
        data = json.loads(match.group(1))
        assert data["mode"] == "single"
        assert data["snapshot"]["metadata"]["hostname"] == "test-machine"

    def test_default_output_path(self, sample_snapshot):
        export_html(str(sample_snapshot))
        assert (sample_snapshot / "snapshot.html").exists()

    def test_missing_db_graceful(self, tmp_path):
        snap = tmp_path / "no_db_snap"
        snap.mkdir()
        (snap / "info.txt").write_text("some info")
        output = str(tmp_path / "output.html")
        export_html(str(snap), output_path=output)
        content = Path(output).read_text()
        assert "some info" in content


class TestExportHtmlDiff:
    def test_creates_html_file(self, sample_snapshot_pair, tmp_path):
        snap_a, snap_b = sample_snapshot_pair
        output = str(tmp_path / "diff.html")
        export_html(str(snap_a), str(snap_b), output_path=output)
        assert Path(output).exists()

    def test_diff_mode_in_data(self, sample_snapshot_pair, tmp_path):
        snap_a, snap_b = sample_snapshot_pair
        output = str(tmp_path / "diff.html")
        export_html(str(snap_a), str(snap_b), output_path=output)
        content = Path(output).read_text()
        match = re.search(r"const DATA = ({.*?});\s*\n", content, re.DOTALL)
        assert match is not None
        data = json.loads(match.group(1))
        assert data["mode"] == "diff"

    def test_diff_summary_counts(self, sample_snapshot_pair, tmp_path):
        snap_a, snap_b = sample_snapshot_pair
        output = str(tmp_path / "diff.html")
        export_html(str(snap_a), str(snap_b), output_path=output)
        content = Path(output).read_text()
        match = re.search(r"const DATA = ({.*?});\s*\n", content, re.DOTALL)
        data = json.loads(match.group(1))
        s = data["sql_diff"]["summary"]
        assert s["new_files"] == 1  # /tmp/newfile.txt
        assert s["deleted_files"] == 1  # /tmp/removed.txt
        assert s["changed_files"] == 1  # /tmp/keep.txt (size+mtime changed)

    def test_diff_has_pref_diffs(self, sample_snapshot_pair, tmp_path):
        snap_a, snap_b = sample_snapshot_pair
        output = str(tmp_path / "diff.html")
        export_html(str(snap_a), str(snap_b), output_path=output)
        content = Path(output).read_text()
        match = re.search(r"const DATA = ({.*?});\s*\n", content, re.DOTALL)
        data = json.loads(match.group(1))
        assert len(data["pref_diffs"]) > 0
        paths = [d["path"] for d in data["pref_diffs"]]
        assert "system_info.txt" in paths

    def test_diff_has_dotfile_diffs(self, sample_snapshot_pair, tmp_path):
        snap_a, snap_b = sample_snapshot_pair
        output = str(tmp_path / "diff.html")
        export_html(str(snap_a), str(snap_b), output_path=output)
        content = Path(output).read_text()
        match = re.search(r"const DATA = ({.*?});\s*\n", content, re.DOTALL)
        data = json.loads(match.group(1))
        assert len(data["dotfile_diffs"]) > 0
        assert data["dotfile_diffs"][0]["status"] == "changed"

    def test_default_output_in_diffs_dir(self, sample_snapshot_pair):
        snap_a, snap_b = sample_snapshot_pair
        result = export_html(str(snap_a), str(snap_b))
        assert "diffs" in result
        assert Path(result).exists()

    def test_self_diff_zero_changes(self, sample_snapshot, tmp_path):
        """Diffing a snapshot with itself should produce zero changes."""
        output = str(tmp_path / "self_diff.html")
        export_html(str(sample_snapshot), str(sample_snapshot), output_path=output)
        content = Path(output).read_text()
        match = re.search(r"const DATA = ({.*?});\s*\n", content, re.DOTALL)
        data = json.loads(match.group(1))
        s = data["sql_diff"]["summary"]
        assert s["new_files"] == 0
        assert s["deleted_files"] == 0
        assert s["changed_files"] == 0
