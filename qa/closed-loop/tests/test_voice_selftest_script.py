"""scripts/voice-selftest.sh summarises the receipt the app writes. The app leaves `firstAudioMs` out for an
engine that did not speak, and the summary must still print every row and its verdict."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/voice-selftest.sh"


def validator():
    text = SCRIPT.read_text()
    start = text.index("<<'PY'\n") + len("<<'PY'\n")
    return text[start:text.index("\nPY\n", start)]


def run(receipt, rc="0"):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        json.dump(receipt, handle)
    return subprocess.run([sys.executable, "-I", "-", handle.name, rc], input=validator(), text=True, capture_output=True)


ROW = {"available": True, "effectPercent": 60, "spoke": False}


class VoiceSelftestSummary(unittest.TestCase):
    def test_a_failed_engine_without_a_first_audio_time_is_summarised(self):
        receipt = {"systemVoice": "Daniel", "rows": [
            dict(ROW, engine="elevenlabs", reason="engine produced no audio"),
            dict(ROW, engine="system", spoke=True, firstAudioMs=488, reason="spoke with Daniel default"),
        ]}
        result = run(receipt)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("elevenlabs  FAILED", result.stdout)
        self.assertIn("PASS", result.stdout)

    def test_samantha_still_fails(self):
        receipt = {"systemVoice": "Samantha", "rows": [dict(ROW, engine="system", spoke=True, firstAudioMs=5, reason="x")]}
        self.assertEqual(run(receipt).returncode, 1)


if __name__ == "__main__":
    unittest.main()
