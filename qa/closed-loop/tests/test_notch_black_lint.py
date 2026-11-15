"""The notch body is pitch black, closed and open, so it reads as part of the hardware notch.

Each check is a function over source text, so every one has a sample that must fail it.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
VIEW = ROOT / "Sources/Zeus/Notch/NotchView.swift"
THEME = ROOT / "Sources/Zeus/App/GlassTheme.swift"

ANCHOR = "let shape = NotchShape(shoulder: shoulder, earHeight: earHeight, bottomRadius: bottomRadius)"


def body_fill_problems(view_text):
    """The fills of `shape` inside the notch body: only Color.black, never an overlay fill or an opacity."""
    start = view_text.index(ANCHOR)
    end = view_text.index("content\n", start)
    region = "\n".join(line.split("//")[0] for line in view_text[start:end].splitlines())
    problems = []
    fills = re.findall(r"\.fill\(([^)]*)\)", region)
    if fills != ["Color.black"]:
        problems.append(f"the body fills are {fills}, not one Color.black")
    if re.search(r"\.overlay\s*\{\s*shape\.fill", region):
        problems.append("a second fill is laid over the black body")
    return problems


def theme_problems(theme_text):
    """No grey or translucent open-panel fill is left to reach for."""
    return [name for name in ("notchPanelFill", "notchPanelOpacity") if re.search(rf"\bstatic let {name}\b", theme_text)]


class NotchBlackLint(unittest.TestCase):
    def test_the_body_is_one_black_fill(self):
        self.assertEqual(body_fill_problems(VIEW.read_text()), [])

    def test_the_theme_has_no_open_panel_gradient(self):
        self.assertEqual(theme_problems(THEME.read_text()), [])

    def test_a_gradient_over_the_black_fails(self):
        sample = ANCHOR + """
                    shape
                        .fill(Color.black)
                        .overlay { shape.fill(Glass.notchPanelFill).opacity(glanceOpen ? 1 : 0) }
            content
"""
        self.assertTrue(body_fill_problems(sample))

    def test_a_grey_fill_fails(self):
        sample = ANCHOR + """
                    shape.fill(Color(white: 0.1))
            content
"""
        self.assertTrue(body_fill_problems(sample))

    def test_a_panel_gradient_in_the_theme_fails(self):
        self.assertEqual(theme_problems("    static let notchPanelFill = LinearGradient(stops: [])\n"), ["notchPanelFill"])


if __name__ == "__main__":
    unittest.main()
