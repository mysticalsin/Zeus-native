"""The open notch panel closes when the pointer leaves even if no mouse-moved event reaches Zeus.

Global mouse monitors go quiet when macOS withholds input access from the app; the panel then stayed open.
Each check is a function over source text, so every one has a sample that must fail it.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
CONTROLLER = ROOT / "Sources/Zeus/Notch/NotchController.swift"


def function_body(text, signature):
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 0
    for index in range(brace, len(text)):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        if depth == 0:
            return text[brace:index]
    raise AssertionError(signature)


def problems(text):
    found = []
    if "func updatePanelWatch()" not in text:
        return ["no panel watch"]
    if "updatePanelWatch()" not in function_body(text, "func show(_ presentation: NotchModel.Presentation)"):
        found.append("show() does not start or stop the panel watch")
    watch = function_body(text, "func updatePanelWatch()")
    if "mouseMoved()" not in watch:
        found.append("the watch does not re-run the pointer check")
    if not re.search(r"presentation\s*==\s*\.panel", watch) or "invalidate()" not in watch:
        found.append("the watch does not run only while the panel is open")
    return found


class PanelClosePollLint(unittest.TestCase):
    def test_the_controller_polls_the_pointer_while_the_panel_is_open(self):
        self.assertEqual(problems(CONTROLLER.read_text()), [])

    def test_a_controller_without_the_watch_fails(self):
        self.assertTrue(problems("func show(_ presentation: NotchModel.Presentation) { model.presentation = presentation }"))

    def test_a_watch_that_never_stops_fails(self):
        sample = """func show(_ presentation: NotchModel.Presentation) { updatePanelWatch() }
func updatePanelWatch() { Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in self.mouseMoved() } }"""
        self.assertTrue(problems(sample))


if __name__ == "__main__":
    unittest.main()
