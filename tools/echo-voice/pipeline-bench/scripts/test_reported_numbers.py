#!/usr/bin/env python3
"""The numbers in the checked-in reports have to match the checked-in data."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "pipeline-bench" / "REPORT.md"
README = ROOT / "README.md"
PARITY = ROOT / "pipeline-bench" / "results"
SUMMARY = ROOT / "bench" / "results" / "summary.md"


def measured_differing_percent() -> float:
    worst = 0.0
    for name in ("parity_python_vs_rust.json", "parity_python_vs_go.json"):
        data = json.loads((PARITY / name).read_text())
        for row in data["files"].values():
            worst = max(worst, float(row["frac_samples_differing"]))
    return 100.0 * worst


class ReportParityTests(unittest.TestCase):
    def test_sample_fraction_covers_the_parity_files(self):
        """EV-NUM-1. parity JSON peaks at 0.1737%, so '<= 0.17%' is false.
        The 3e-7 float claim is not in those files."""
        measured = measured_differing_percent()
        self.assertGreater(measured, 0.17)
        self.assertLess(measured, 0.174)
        for path in (REPORT, README):
            text = path.read_text()
            self.assertNotIn("3e-7", text, path.name)
            compact = text.replace(" ", "")
            self.assertNotIn("0.17%", compact, path.name)
            self.assertIn("0.174%", compact, path.name)


if __name__ == "__main__":
    unittest.main()
