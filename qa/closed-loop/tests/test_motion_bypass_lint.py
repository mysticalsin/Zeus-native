"""Overlay and avatar motion goes through Motion.reducible, so Reduce Motion can turn it off."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
FILES = [
    ROOT / "Sources/Zeus/Overlay/BuddyOverlayView.swift",
    ROOT / "Sources/Zeus/Avatar/LivingMascot.swift",
    ROOT / "Sources/Zeus/Avatar/Avatar.swift",
]
RAW = re.compile(r"(?:withAnimation|\.animation)\((?!Motion\.reducible\b)")


def code_lines(text):
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip().startswith("//"):
            yield number, line


class MotionBypassLint(unittest.TestCase):
    def test_overlay_and_avatar_animation_uses_the_motion_helper(self):
        raw = []
        for path in FILES:
            text = path.read_text()
            for number, line in code_lines(text):
                if RAW.search(line):
                    raw.append(f"{path.relative_to(ROOT)}:{number}: {line.strip()}")
        self.assertEqual(raw, [])


if __name__ == "__main__":
    unittest.main()
