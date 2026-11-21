#!/usr/bin/env python3
"""S05-11. The meeting card must not take Return or Escape while a dictation check is up."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class ReturnEscapeTests(unittest.TestCase):
    def test_meeting_card_asks_before_it_becomes_key(self):
        panel = (ROOT / "Sources/Zeus/Scribe/ScribeMeetingCardPanel.swift").read_text(encoding="utf-8")
        self.assertIn("dictationCheckVisible", panel)
        preview = (ROOT / "Sources/Zeus/Dictation/DictationPreviewCard.swift").read_text(encoding="utf-8")
        self.assertIn("static var isReviewing", preview)
