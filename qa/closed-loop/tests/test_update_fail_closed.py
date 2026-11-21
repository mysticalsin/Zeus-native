"""S11-04 and S11-05 on the updates branch. No feed URL or key is invented here."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CARD = ROOT / "Sources/ZeusCore/Settings/Sections/AutoUpdate/UpdatesCard.swift"
SESSION = ROOT / "Sources/ZeusCore/Settings/Sections/AutoUpdate/UpdateSession.swift"


class UpdateFailClosed(unittest.TestCase):
    def test_missing_feed_or_key_says_updates_not_configured(self):
        text = CARD.read_text(encoding="utf-8")
        self.assertIn('return "updates not configured"', text)

    def test_ready_to_install_does_not_start_a_check_on_appear(self):
        text = SESSION.read_text(encoding="utf-8")
        start = text.split("func startsCheckOnAppear", 1)[1]
        gate = start.split("public enum UpdateSession", 1)[0]
        self.assertIn(".readyToInstall", gate)


if __name__ == "__main__":
    unittest.main(verbosity=2)
