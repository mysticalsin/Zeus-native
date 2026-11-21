"""The quiet top bar is sRGB black. Hover, peek and the open panel keep the gated Color.black fill.

The quiet branch fills with TopBarIdleBlack.color and nothing else. The Transparent island background still gates
the hover and open fill, the outline stroke and the glow on the pure `NotchBackground` layers.

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
    """Quiet bar: TopBarIdleBlack.color with no glass. Hover and open: one gated Color.black."""
    start = view_text.index(ANCHOR)
    end = view_text.index("content\n", start)
    region = "\n".join(line.split("//")[0] for line in view_text[start:end].splitlines())
    problems = []
    fills = re.findall(r"\.fill\(([^)]*)\)", region)
    if fills != ["TopBarIdleBlack.color", "Color.black"]:
        problems.append(f"the body fills are {fills}, not TopBarIdleBlack.color then Color.black")
    if re.search(r"\.overlay\s*\{\s*shape\.fill", region):
        problems.append("a second fill is laid over the black body")
    if not re.search(r"\.fill\(Color\.black\)\s*\.opacity\(drawn\.fill \? 1 : 0\)", region):
        problems.append("the black fill is not gated on the background layers (Transparent would still be black)")
    if not re.search(r"shape\.stroke\([^\n]*drawn\.outline", region):
        problems.append("the outline stroke is not gated on the background layers")
    if not re.search(r"glowsOutline\(status: status\) && drawn\.glow", view_text):
        problems.append("the glow is not gated on the background layers")
    idle = idle_branch(region)
    if idle is None:
        problems.append("the quiet bar has no pitch-black branch")
    else:
        for token in (".opacity", ".shadow", ".blur", "Material", "Gradient", "NSVisualEffect", "ultraThin"):
            if token in idle:
                problems.append(f"the quiet fill uses {token}")
    return problems


def idle_branch(region):
    marker = "if pitchBlack {"
    if marker not in region or "} else {" not in region:
        return None
    start = region.index(marker) + len(marker)
    return region[start:region.index("} else {", start)]


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
                        .fill(Color.black).opacity(drawn.fill ? 1 : 0)
                        .overlay { shape.fill(Glass.notchPanelFill).opacity(glanceOpen ? 1 : 0) }
            content
"""
        self.assertTrue(body_fill_problems(sample))

    def test_an_ungated_black_fill_fails(self):
        sample = ANCHOR + """
                    shape.fill(Color.black)
                    shape.stroke(glow.opacity(0.5), lineWidth: 1.2)
            content
"""
        self.assertTrue(any("not gated" in p for p in body_fill_problems(sample)))

    def test_the_gated_fill_outline_and_glow_pass(self):
        sample = ANCHOR + """
                    if pitchBlack {
                        shape.fill(TopBarIdleBlack.color)
                    } else {
                        shape
                            .fill(Color.black)
                            .opacity(drawn.fill ? 1 : 0)
                        shape.stroke(glow.opacity(glowing && drawn.outline ? 0.5 : 0), lineWidth: 1.2)
                    }
            content
        let glowing = glowsOutline(status: status) && drawn.glow
"""
        self.assertEqual(body_fill_problems(sample), [])

    def test_a_shadow_on_the_quiet_fill_fails(self):
        sample = ANCHOR + """
                    if pitchBlack {
                        shape.fill(TopBarIdleBlack.color).shadow(color: .black, radius: 4)
                    } else {
                        shape.fill(Color.black)
                            .opacity(drawn.fill ? 1 : 0)
                        shape.stroke(glow.opacity(drawn.outline ? 0.5 : 0), lineWidth: 1.2)
                    }
            content
        let glowing = glowsOutline(status: status) && drawn.glow
"""
        self.assertTrue(any("quiet fill" in problem for problem in body_fill_problems(sample)))

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
