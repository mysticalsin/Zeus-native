#!/usr/bin/env python3
"""S05-13. Save and file failures shown to a person do not include the system error text."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class ShownFailureTests(unittest.TestCase):
    def test_scribe_and_dictation_use_plain_sentences(self):
        scribe = (ROOT / "Sources/Zeus/Scribe/ScribeController.swift").read_text(encoding="utf-8")
        self.assertIn("ShownFailure.meetingSave", scribe)
        self.assertIn("ShownFailure.meetingNotes", scribe)
        self.assertNotIn("notes couldn't be written (\\(error.localizedDescription))", scribe)
        dictation = (ROOT / "Sources/Zeus/Dictation/DictationController.swift").read_text(encoding="utf-8")
        self.assertIn("ShownFailure.dictationFile", dictation)
        self.assertIn("ShownFailure.engine", dictation)
        self.assertNotIn("Couldn't read the file here:", dictation)
