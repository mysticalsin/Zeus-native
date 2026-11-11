"""Alerts surfaces (docs/ALERTS-DESIGN.md) must own no clock while idle.

Every alert animation is a one-shot SwiftUI animation. A Timer, TimelineView, display link or repeating animation
in Sources/Zeus/Alerts would keep running with nothing to show, so none may appear there. Auto-dismiss is one
cancellable sleep to the next deadline (NotchController.alertsChanged), never polling.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
ALERTS = ROOT / "Sources/Zeus/Alerts"
CONTROLLER = ROOT / "Sources/Zeus/Notch/NotchController.swift"
FORBIDDEN = re.compile(
    r"\bTimer\b|\bTimelineView\b|\bDisplaySynchronizedView\b|\bCVDisplayLink\b|\bCADisplayLink\b|\.repeatForever\b|\bTickingView\b")


def code_lines(text):
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip().startswith("//"):
            yield number, line.split("//")[0] if "//" in line and '"' not in line else line


def offenders(text, label="sample"):
    return [f"{label}:{n}" for n, line in code_lines(text) if FORBIDDEN.search(line)]


class AlertsIdleLint(unittest.TestCase):
    def test_alert_views_have_no_timer_display_link_or_repeating_animation(self):
        files = sorted(ALERTS.glob("*.swift"))
        self.assertTrue(files, "Sources/Zeus/Alerts is missing")
        found = []
        for path in files:
            found += offenders(path.read_text(), path.relative_to(ROOT).as_posix())
        self.assertEqual(found, [])

    def test_auto_dismiss_is_one_cancellable_sleep_to_the_next_deadline(self):
        text = CONTROLLER.read_text()
        body = text[text.index("private func alertsChanged()"):]
        body = body[:body.index("\n    }\n")]
        self.assertIn("alertWake?.cancel()", body)
        self.assertIn("nextDeadline()", body)
        self.assertEqual(len(re.findall(r"Task\.sleep", body)), 1)
        self.assertNotIn("Timer", body)

    def test_idle_lint_detects_its_failure_shapes(self):
        self.assertTrue(offenders("TimelineView(.animation) { _ in }"))
        self.assertTrue(offenders("DisplaySynchronizedView(paused: false) { _ in }"))
        self.assertTrue(offenders(".animation(.linear.repeatForever(autoreverses: false), value: x)"))
        self.assertTrue(offenders("let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in }"))
        self.assertFalse(offenders("// a Timer would keep running"))
        self.assertFalse(offenders("withAnimation(.linear(duration: 1.2)) { sweep = 1 }"))


class AlertsStyleLint(unittest.TestCase):
    def test_alert_sources_have_no_em_dash_and_use_the_shared_material(self):
        for path in sorted(ALERTS.glob("*.swift")):
            self.assertNotIn("—", "\n".join(line for _, line in code_lines(path.read_text())), path.name)
        for relative in ("Sources/Zeus/Proactive/BriefCard.swift", "Sources/Zeus/Scribe/ScribeCallPopup.swift"):
            self.assertIn(".alertGlass(", (ROOT / relative).read_text(), relative)


if __name__ == "__main__":
    unittest.main()
