"""S11-13 on the approval-queue branch: pending cards have a cap."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class ApprovalQueueCap(unittest.TestCase):
    def test_pending_cards_stop_at_forty(self):
        text = (ROOT / "Sources/Zeus/Notch/NotchController.swift").read_text(encoding="utf-8")
        self.assertIn("static let maxPendingApprovals = 40", text)
        self.assertGreaterEqual(text.count("pendingApprovals.count >= Self.maxPendingApprovals"), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
