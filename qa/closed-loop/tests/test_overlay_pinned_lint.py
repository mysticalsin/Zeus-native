"""The island and the screen overlays stay pinned to the screen edge: no system window animation, no ghost windows.

A borderless panel keeps AppKit's default window animation unless told otherwise. When a top bar panel was ordered out
during a rebuild (wake, screen change), the system zoom-out stuck part way: a ghost copy of the island stayed on screen
at 98 percent scale, 4 pt below the top edge (window 1764 x 462 at 18, 4 on a 1800 x 470 frame), so the owner saw a strip
of wallpaper between the island and the screen edge. Every overlay window is created with `animationBehavior = .none`,
and a rebuild closes the windows it drops instead of only ordering them out.

Each check is a function over source text, so every one has a sample that must fail it.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
OVERLAYS = [
    ROOT / "Sources/Zeus/Notch/NotchController.swift",
    ROOT / "Sources/Zeus/Notch/ScreenEdgeGlowController.swift",
    ROOT / "Sources/Zeus/Notch/EdgeWave.swift",
    ROOT / "Sources/Zeus/Notch/ScreenCornerOverlay.swift",
    ROOT / "Sources/Zeus/Overlay/BuddyController.swift",
]
CREATION = re.compile(r"\b(?:NSPanel|NSWindow|NotchPanel)\(contentRect:")


def unpinned_creations(text):
    """Window creations whose enclosing function (or a flags type it applies) never turns the system animation off."""
    code = "\n".join(line.split("//")[0] for line in text.splitlines())
    problems = []
    for match in CREATION.finditer(code):
        start = code.rfind("func ", 0, match.start())
        end = code.find("\n    }\n", match.end())
        body = code[start:end if end != -1 else len(code)]
        if "animationBehavior = .none" in body:
            continue
        if re.search(r"\b\w+\.apply\(to: panel\)", body) and "panel.animationBehavior = .none" in code:
            continue
        line = code.count("\n", 0, match.start()) + 1
        problems.append(f"line {line}: window created without animationBehavior = .none")
    return problems


def rebuild_problems(text, function, collection):
    """The rebuild closes every window it drops, not only orders it out."""
    start = text.index(f"private func {function}()")
    body = text[start:text.index("\n    }\n", start)]
    if not re.search(rf"{collection}[^\n]*\.close\(\)", body):
        return [f"{function} orders old windows out without closing them"]
    return []


class OverlayPinnedLint(unittest.TestCase):
    def test_every_overlay_window_turns_the_system_animation_off(self):
        for path in OVERLAYS:
            with self.subTest(path=path.name):
                self.assertEqual(unpinned_creations(path.read_text(encoding="utf-8")), [])

    def test_rebuilds_close_the_windows_they_drop(self):
        notch = (ROOT / "Sources/Zeus/Notch/NotchController.swift").read_text(encoding="utf-8")
        buddy = (ROOT / "Sources/Zeus/Overlay/BuddyController.swift").read_text(encoding="utf-8")
        self.assertEqual(rebuild_problems(notch, "build", "for entry in panels"), [])
        self.assertEqual(rebuild_problems(buddy, "rebuildWindows", "windows.forEach"), [])

    def test_samples_that_must_fail(self):
        bare = "    private func make() -> NSPanel {\n        let panel = NSPanel(contentRect: .zero)\n        return panel\n    }\n"
        self.assertTrue(unpinned_creations(bare))
        commented = bare.replace("return panel", "// panel.animationBehavior = .none\n        return panel")
        self.assertTrue(unpinned_creations(commented))
        pinned = bare.replace("return panel", "panel.animationBehavior = .none\n        return panel")
        self.assertFalse(unpinned_creations(pinned))
        hidden = "    private func build() {\n        for entry in panels { entry.panel.orderOut(nil) }\n    }\n"
        self.assertTrue(rebuild_problems(hidden, "build", "for entry in panels"))
        closed = hidden.replace("orderOut(nil) }", "orderOut(nil); entry.panel.close() }")
        self.assertFalse(rebuild_problems(closed, "build", "for entry in panels"))


if __name__ == "__main__":
    unittest.main()
