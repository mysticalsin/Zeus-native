#!/usr/bin/env python3
"""The Echo tree names the Apache-2.0 notices for Haru and Kokoro."""
import unittest
from pathlib import Path

NOTICE = Path(__file__).resolve().parents[2] / "NOTICE"


class NoticeTests(unittest.TestCase):
    def test_notice_names_apache_haru_and_kokoro(self):
        text = NOTICE.read_text(encoding="utf-8")
        self.assertIn("Apache-2.0", text)
        self.assertIn("Haru", text)
        self.assertIn("Kokoro", text)


if __name__ == "__main__":
    unittest.main()
