"""About ships Resources/NOTICES.txt. The speech and voice sections must be in that file."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SHIPPED = ROOT / "Resources" / "NOTICES.txt"
REQUIRED = (
    "## Speech to text (Murmure dictation and voice turns)",
    "## Text to speech (Settings › Voice, optional)",
)


class BundledNotices(unittest.TestCase):
    def test_shipped_notices_include_speech_and_voice(self):
        text = SHIPPED.read_text(encoding="utf-8")
        missing = [heading for heading in REQUIRED if heading not in text]
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
