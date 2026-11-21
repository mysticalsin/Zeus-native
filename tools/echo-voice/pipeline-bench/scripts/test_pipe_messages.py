#!/usr/bin/env python3
"""pipe.py should say what is wrong with a manifest, not print a traceback."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PIPE = Path(__file__).resolve().parents[1] / "python" / "pipe.py"


def run(wl: Path, mode: str = "file") -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(PIPE), "bench", "--workload", str(wl), "--out", str(wl / "out"), "--mode", mode],
        capture_output=True, text=True,
    )


class ManifestMessageTests(unittest.TestCase):
    def assert_refused(self, proc: subprocess.CompletedProcess[str], needle: str) -> None:
        self.assertEqual(proc.returncode, 2, proc.stderr)
        self.assertNotIn("Traceback", proc.stderr)
        self.assertIn("haru-pipe:", proc.stderr)
        self.assertIn(needle, proc.stderr)

    def test_bad_manifest_is_one_sentence(self):
        with tempfile.TemporaryDirectory() as td:
            wl = Path(td)
            (wl / "out").mkdir()
            (wl / "manifest.json").write_text("not-json")
            self.assert_refused(run(wl), "manifest")
            (wl / "manifest.json").unlink()
            self.assert_refused(run(wl), "manifest")
            (wl / "manifest.json").write_text("{}")
            self.assert_refused(run(wl), "manifest")
            (wl / "manifest.json").write_text(json.dumps({"files": [], "stream": {"file": "unused.f32"}}))
            self.assert_refused(run(wl), "no audio")


if __name__ == "__main__":
    unittest.main()
