#!/usr/bin/env python3
"""Screen-reader text for the chart and the bench reports."""
from __future__ import annotations

import json
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SVG = ROOT / "docs" / "stream-latency.svg"
SUMMARY = ROOT / "pipeline-bench" / "results" / "summary.json"
TABLE = ROOT / "pipeline-bench" / "results" / "table.md"
BENCH = ROOT / "bench" / "results" / "summary.md"
NS = {"svg": "http://www.w3.org/2000/svg"}


def dumped(value: float) -> str:
    return json.dumps(value)


class AccessibilityTests(unittest.TestCase):
    def test_chart_description_includes_p50_and_p95(self):
        summary = json.loads(SUMMARY.read_text())
        root = ET.fromstring(SVG.read_text())
        desc = root.find("svg:desc", NS)
        self.assertIsNotNone(desc)
        text = desc.text or ""
        self.assertIn("p95", text)
        for impl in ("python", "rust", "go"):
            self.assertIn(dumped(summary[impl]["stream_frame_p50_ms"]), text, impl)
            self.assertIn(dumped(summary[impl]["stream_frame_p95_ms"]), text, impl)

    def test_results_table_has_a_heading(self):
        lines = [line for line in TABLE.read_text().splitlines() if line.strip()]
        self.assertTrue(lines[0].startswith("# "), lines[0])
        self.assertIn("| Python", "\n".join(lines))
        self.assertIn("|---", "\n".join(lines))

    def test_bench_summary_points_at_the_report_in_this_tree(self):
        text = BENCH.read_text()
        self.assertNotIn("/workspace/echo", text)
        target = (BENCH.parent / "../../pipeline-bench/REPORT.md").resolve()
        self.assertTrue(target.is_file(), target)
        self.assertIn("../../pipeline-bench/REPORT.md", text)


if __name__ == "__main__":
    unittest.main()
