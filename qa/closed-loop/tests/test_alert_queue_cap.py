"""S11-13 on integration: the in-app alert queue and outgoing banner budget are capped."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class AlertQueueCap(unittest.TestCase):
    def test_alert_stack_drops_past_forty(self):
        text = (ROOT / "Sources/ZeusCore/Alerts/AlertStack.swift").read_text(encoding="utf-8")
        self.assertIn("static let maxQueued = 40", text)
        self.assertIn("items.count > Self.maxQueued", text)

    def test_outgoing_banners_keep_forty(self):
        text = (ROOT / "Sources/ZeusCore/Alerts/NotificationDeliveryBudget.swift").read_text(encoding="utf-8")
        self.assertIn("static let maxOutstanding = 40", text)
        service = (ROOT / "Sources/Zeus/App/SystemNotificationService.swift").read_text(encoding="utf-8")
        self.assertIn("NotificationDeliveryBudget", service)


if __name__ == "__main__":
    unittest.main(verbosity=2)
