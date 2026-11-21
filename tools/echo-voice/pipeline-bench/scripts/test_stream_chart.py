#!/usr/bin/env python3
"""The stream-latency chart has to show the measured bars with motion off."""
from __future__ import annotations

import json
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SVG = ROOT / "docs" / "stream-latency.svg"
SUMMARY = ROOT / "pipeline-bench" / "results" / "summary.json"
NS = {"svg": "http://www.w3.org/2000/svg"}
FILLS = {"python": "#b45309", "rust": "#0f766e", "go": "#1d4ed8"}


def px(value: float, scale: float) -> float:
    return round(value / scale * 320.0, 1)


class StreamChartTests(unittest.TestCase):
    def test_bars_are_visible_without_animation(self):
        summary = json.loads(SUMMARY.read_text())
        scale = summary["python"]["stream_frame_p95_ms"]
        text = SVG.read_text()
        root = ET.fromstring(text)
        for impl, fill in FILLS.items():
            rects = [el for el in root.iterfind(".//svg:rect", NS) if el.get("fill") == fill]
            self.assertEqual(len(rects), 1, impl)
            width = float(rects[0].get("width"))
            self.assertEqual(width, px(summary[impl]["stream_frame_p50_ms"], scale), impl)
            self.assertGreater(width, 0, impl)
        lines = [el for el in root.iterfind(".//svg:line", NS) if el.get("stroke") == "#1c1917"]
        self.assertEqual(len(lines), 3)
        ticks = sorted(float(el.get("x1")) for el in lines)
        expect = [
            px(summary[impl]["stream_frame_p95_ms"], scale)
            for impl in ("rust", "go", "python")
        ]
        self.assertEqual(ticks, sorted(expect))
        self.assertIn("prefers-reduced-motion: reduce", text)
        self.assertIn("animation: none", text)
        self.assertEqual(list(root.iterfind(".//svg:animate", NS)), [])


if __name__ == "__main__":
    unittest.main()
