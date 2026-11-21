"""S11-13 on the hub decision branch: the waiting list has a cap."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class HubQueueCap(unittest.TestCase):
    def test_waiting_list_stops_at_forty(self):
        text = (ROOT / "Sources/ZeusCore/AgentHub/HubDecision.swift").read_text(encoding="utf-8")
        self.assertIn("static let maxWaiting = 40", text)
        self.assertIn("next.waiting.count >= Self.maxWaiting", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
