"""Settings glass follows the stored window appearance. Linux reads the palette source."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
CORE = ROOT / "Sources/ZeusCore/Settings/WindowGlassPalette.swift"
STYLE = ROOT / "Sources/Zeus/Settings/GlanceSettingsStyle.swift"
WINDOW = ROOT / "Sources/Zeus/Settings/GlanceSettingsWindow.swift"

DARK = {
    "window": (20, 22, 27),
    "panel": (31, 32, 37),
    "panelStroke": (53, 54, 59),
    "card": (35, 37, 44),
    "cardStroke": (61, 63, 69),
    "separator": (55, 57, 63),
    "text": (241, 243, 248),
    "secondary": (173, 181, 195),
    "selectedFill": (38, 56, 86),
    "selectedText": (128, 178, 249),
    "buttonFill": (20, 22, 27),
    "buttonStroke": (48, 50, 54),
    "controlFill": (54, 57, 66),
    "controlStroke": (104, 109, 122),
    "controlText": (232, 235, 242),
    "toggleOff": (89, 91, 97),
    "knob": (230, 231, 232),
}


def channel(byte):
    value = byte / 255
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def contrast(a, b):
    def luminance(rgb):
        return 0.2126 * channel(rgb[0]) + 0.7152 * channel(rgb[1]) + 0.0722 * channel(rgb[2])
    lighter = max(luminance(a), luminance(b))
    darker = min(luminance(a), luminance(b))
    return (lighter + 0.05) / (darker + 0.05)


def tokens(text, name):
    start = text.index(f"public static let {name} = Tokens(")
    rest = text[start:]
    end = rest.index("\n    public static ")
    found = {}
    for key, red, green, blue in re.findall(r"(\w+): RGB\((\d+), (\d+), (\d+)\)", rest[:end]):
        found[key] = (int(red), int(green), int(blue))
    return found


class WindowGlassPalette(unittest.TestCase):
    def setUp(self):
        self.core = CORE.read_text(encoding="utf-8")
        self.style = STYLE.read_text(encoding="utf-8")
        self.window = WINDOW.read_text(encoding="utf-8")

    def test_core_palette_is_pure_and_keeps_todays_dark_glass(self):
        code = "\n".join(line.split("//")[0] for line in self.core.splitlines())
        for forbidden in ("import AppKit", "import SwiftUI", "UserDefaults", "NSApp"):
            self.assertNotIn(forbidden, code)
        self.assertNotIn("\u2014", self.core)
        self.assertNotIn("\u2013", self.core)
        dark = tokens(self.core, "dark")
        light = tokens(self.core, "light")
        self.assertEqual(dark, DARK)
        self.assertEqual(set(light), set(DARK))
        self.assertNotEqual(light["window"], dark["window"])
        self.assertNotEqual(light["text"], dark["text"])

    def test_text_clears_the_settings_surfaces(self):
        self.assertAlmostEqual(contrast((0, 0, 0), (255, 255, 255)), 21, places=5)
        for name in ("dark", "light"):
            palette = tokens(self.core, name)
            for ink, surface in (
                ("text", "window"), ("text", "panel"), ("text", "card"),
                ("secondary", "window"), ("secondary", "card"),
                ("selectedText", "selectedFill"), ("controlText", "controlFill"),
            ):
                ratio = contrast(palette[ink], palette[surface])
                self.assertGreaterEqual(ratio, 4.5, f"{name} {ink}/{surface} {ratio:.2f}")
        light = tokens(self.core, "light")
        self.assertGreaterEqual(contrast(light["controlStroke"], light["card"]), 3)

    def test_settings_root_follows_the_stored_choice(self):
        self.assertIn('case "Light": .light', self.core)
        self.assertIn('case "Dark": .dark', self.core)
        self.assertIn("systemIsLight ? .light : .dark", self.core)
        self.assertIn("WindowGlassPalette.resolve(stored:", self.window)
        self.assertIn("WindowGlassAppearance.install(resolved)", self.window)
        self.assertNotIn(".preferredColorScheme(.dark)", self.window)
        self.assertIn("WindowGlassPalette.tokens(WindowGlassAppearance.resolved)", self.style)
        pages = (ROOT / "Sources/Zeus/Settings/GlanceSettingsPages.swift").read_text(encoding="utf-8")
        self.assertNotIn("WindowGlassPalette", pages)
