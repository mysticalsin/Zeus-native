"""A running dictation turn still asks the store to drop old audio."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
CONTROLLER = ROOT / "Sources/Zeus/Dictation/DictationController.swift"


class DictationAudioPrune(unittest.TestCase):
    def test_a_turn_end_still_calls_prune(self):
        source = CONTROLLER.read_text()
        self.assertGreaterEqual(source.count("pruneStoredAudioIfDue()"), 4)
        start = source.index("func pruneStoredAudioIfDue")
        body = source[start:source.index("\n    private", start)]
        self.assertIn("store.prune(olderThanDays:", body)


if __name__ == "__main__":
    unittest.main()
