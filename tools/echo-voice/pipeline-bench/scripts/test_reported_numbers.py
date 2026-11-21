#!/usr/bin/env python3
"""The numbers in the checked-in reports have to match the checked-in data."""
from __future__ import annotations

import json
import statistics
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


def stage_rows(text: str) -> dict[str, list[float]]:
    rows = {}
    for line in text.splitlines():
        if not line.startswith("| ") or line.startswith("| run") or line.startswith("|---"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 9 or cells[0] in {"run"}:
            continue
        try:
            rows[cells[0]] = [float(c) for c in cells[1:]]
        except ValueError:
            continue
    return rows


class SummaryStageTests(unittest.TestCase):
    def test_stage_sums_and_host_share(self):
        """EV-NUM-2. The sum column has to be the sum of the stage cells.
        0.04 / 80.81 is 0.05%, not 0.06%. Figures with no per-item file
        in this tree must say so."""
        text = SUMMARY.read_text()
        rows = stage_rows(text)
        for name, expect in (("bf16 FR", 123.27), ("bf16 EN", 146.43), ("q8 FR", 86.55), ("q8 EN", 81.98)):
            got = rows[name]
            self.assertAlmostEqual(sum(got[:-1]), got[-1], places=2, msg=name)
            self.assertAlmostEqual(got[-1], expect, places=2, msg=name)
        self.assertNotIn("0.06 %", text)
        self.assertIn("0.05 %", text)
        self.assertIn("not in this tree", text)


class RawJsonlTests(unittest.TestCase):
    def test_summary_medians_match_raw_jsonl(self):
        raw = [json.loads(line) for line in (PARITY / "raw.jsonl").read_text().splitlines() if line.strip()]
        summary = json.loads((PARITY / "summary.json").read_text())
        for impl in ("python", "rust", "go"):
            benches = [r for r in raw if r["impl"] == impl and r["kind"] == "bench"]
            self.assertEqual(summary[impl]["runs"], len(benches))
            got = statistics.median(r["stream"]["per_frame"]["p50_ms"] for r in benches)
            self.assertAlmostEqual(got, summary[impl]["stream_frame_p50_ms"], places=6)
            got95 = statistics.median(r["stream"]["per_frame"]["p95_ms"] for r in benches)
            self.assertAlmostEqual(got95, summary[impl]["stream_frame_p95_ms"], places=6)
            walls = statistics.median(r["stream"]["wall_s"] for r in benches)
            self.assertAlmostEqual(walls, summary[impl]["stream_wall_s"], places=6)


class ReproduceCommandTests(unittest.TestCase):
    def test_report_commands_use_this_tree(self):
        text = REPORT.read_text()
        self.assertNotIn("/workspace/echo", text)
        self.assertNotIn("package/haru-pipe", text)


if __name__ == "__main__":
    unittest.main()
