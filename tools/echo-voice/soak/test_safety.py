#!/usr/bin/env python3
"""Safety regressions for the Echo soak harness. Each test names the sweep that found it."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SOAK = Path(__file__).resolve().parent
HARNESS = SOAK / "haru_soak.py"


class ShortRunTests(unittest.TestCase):
    def test_warmup_only_run_writes_metrics_and_exits_0(self):
        """A run whose frames never pass the warm-up cutoff (k > 16) must still
        finish: metrics.json and replies.jsonl exist, and the process exits 0.
        0.03 min is about 13 frames, all inside the warm-up window."""
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "short"
            proc = subprocess.run(
                [sys.executable, str(HARNESS), "run", "--backend", "fake", "--fake-audio",
                 "--out", str(out), "--minutes", "0.03", "--sample-seconds", "0"],
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr[-800:] + proc.stdout[-400:])
            metrics = json.loads((out / "metrics.json").read_text())
            self.assertEqual(metrics["frames_logged"] > 0, True)
            self.assertTrue((out / "replies.jsonl").is_file())


if __name__ == "__main__":
    unittest.main()
