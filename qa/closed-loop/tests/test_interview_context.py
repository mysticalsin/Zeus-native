"""Candidate context is stored locally. The interview page still does not record a call."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
CORE = ROOT / "Sources/ZeusCore/Interview/InterviewContext.swift"
PREFS = ROOT / "Sources/Zeus/App/ExtraPreferences.swift"
PAGE = ROOT / "Sources/Zeus/App/SettingsExtraPages.swift"
CATALOG = ROOT / "Sources/Zeus/App/SettingsCatalog.swift"
DELEGATE = ROOT / "Sources/Zeus/App/AppDelegate.swift"


class InterviewContextStore(unittest.TestCase):
    def test_core_note_is_local_and_bounded(self):
        text = CORE.read_text(encoding="utf-8")
        code = "\n".join(line.split("//")[0] for line in text.splitlines())
        for forbidden in ("import AppKit", "import SwiftUI", "URLSession", "AVAudio", "UserDefaults"):
            self.assertNotIn(forbidden, code)
        self.assertIn('public static let storageKey = "opt.interview.context"', text)
        self.assertIn("public static let limit = 2000", text)
        self.assertIn("trimmingCharacters(in: .whitespacesAndNewlines)", text)
        self.assertIn("String(trimmed.prefix(limit))", text)
        self.assertNotIn("\u2014", text)
        self.assertNotIn("\u2013", text)

    def test_the_page_stores_the_note_and_still_does_not_record(self):
        prefs = PREFS.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn("InterviewContext.storageKey", prefs)
        self.assertIn("InterviewContext.normalize", prefs)
        self.assertIn("candidateContext", page)
        self.assertIn("nothing here records anyone", page)
        self.assertIn("Stays on this Mac", page)
        self.assertNotIn("AVAudio", page)
        self.assertNotIn("URLSession", page)
        self.assertNotIn("InterviewContext", CATALOG.read_text(encoding="utf-8"))
        self.assertNotIn("InterviewContext", DELEGATE.read_text(encoding="utf-8"))
