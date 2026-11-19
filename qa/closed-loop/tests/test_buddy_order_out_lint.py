"""The buddy's full-screen overlay leaves the screen while the buddy is hidden.

An invisible window at the screen-saver level stayed ordered in on every display, so windows under it (other apps'
too) could report themselves occluded and pause. Each check is a function over source text, so every one has a sample
that must fail it.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BUDDY = ROOT / "Sources/Zeus/Overlay/BuddyController.swift"


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
    visibility = function_body(text, "private func applyVisibility(")
    if "orderOut(" not in visibility:
        found.append("hiding never takes the overlay off the screen")
    if "orderFrontRegardless()" not in visibility:
        found.append("showing never puts the overlay back")
    rebuild = function_body(text, "private func rebuildWindows()")
    if "orderFrontRegardless()" in rebuild and "if shownAlpha != 0" not in rebuild:
        found.append("a rebuild orders a hidden overlay in")
    return found


class BuddyOrderOutLint(unittest.TestCase):
    def test_a_hidden_buddy_leaves_no_window_on_screen(self):
        self.assertEqual(problems(BUDDY.read_text()), [])

    def test_alpha_only_hiding_fails(self):
        sample = """private func applyVisibility(animated: Bool = true) { window.alphaValue = target }
private func rebuildWindows() { window.orderFrontRegardless() }"""
        self.assertTrue(problems(sample))


if __name__ == "__main__":
    unittest.main()
