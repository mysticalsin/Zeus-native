"""The open panel is absolute black behind its content: no ambient glow, no grey chrome, no grey card fill.

The owner asked for pitch black. A render of the panel showed the body at 0,0,0 but the tab capsule, the more
button and the Home cards at about 19 to 24 grey, and a tinted glow behind the cards. Each check is a function over
source text, so every one has a sample that must fail it.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
VIEW = ROOT / "Sources/Zeus/Notch/NotchView.swift"
CARDS = ROOT / "Sources/Zeus/TopBar/GlanceHomeCards.swift"


def view_problems(text):
    return ["the open panel draws an ambient glow"] if "RadialGradient(colors: [contentGlow" in text else []


def tint_problems(text):
    found = []
    for name in ("capsule", "more"):
        m = re.search(rf"static let {name} = (.+)", text)
        if not m or m.group(1).strip() != "Color.black":
            found.append(f"GlanceTint.{name} is not Color.black")
    return found


def card_problems(text):
    start = text.index("case .glass?, .liquidGlass?:")
    block = text[start:text.index("case let finish?:", start)]
    found = []
    if "tint.opacity(0.08)" in block:
        found.append("glass cards are tinted grey")
    if "Color.white.opacity(0.035)" in block:
        found.append("glass cards are lifted with a white gradient")
    if "strokeBorder" not in block:
        found.append("glass cards lost their edge")
    return found


class PanelAbsoluteBlackLint(unittest.TestCase):
    def test_the_panel_has_no_ambient_glow(self):
        self.assertEqual(view_problems(VIEW.read_text()), [])

    def test_the_tab_capsule_and_more_button_are_black(self):
        self.assertEqual(tint_problems(CARDS.read_text()), [])

    def test_home_cards_are_black_with_an_edge(self):
        self.assertEqual(card_problems(CARDS.read_text()), [])

    def test_samples_fail(self):
        self.assertTrue(view_problems("RadialGradient(colors: [contentGlow.opacity(0.35), .clear])"))
        self.assertTrue(tint_problems("static let capsule = Color(red: 19 / 255, green: 19 / 255, blue: 21 / 255)\nstatic let more = Color.black"))
        self.assertTrue(card_problems("case .glass?, .liquidGlass?:\n shape.fill(tint.opacity(0.08)) .strokeBorder(x)\ncase let finish?:"))


if __name__ == "__main__":
    unittest.main()
