"""The playback toggles that already have readers are drawn on the Music source card."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
PAGES = ROOT / "Sources/Zeus/Settings/GlanceSettingsPages.swift"

# Title is the catalog title. The id is the constant the existing reader already uses.
ROWS = (
    ("Collapse when paused", "PlaybackCollapse.settingID"),
    ("Show what this Mac is playing", "SystemNowPlayingLaunch.settingID"),
    ("Show receiver names", "ReceiverCatalog.settingID"),
    ("Earbud overlay", "EarbudOverlayRule.settingID"),
    ("Show the Focus name", "FocusNameStore.settingID"),
    ("Lock screen player", "LockScreenPlayerGate.settingID"),
)


def function_body(text, signature):
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 0
    for index in range(brace, len(text)):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        if depth == 0:
            return text[brace:index + 1]
    raise AssertionError(signature)


def playback_surface(text):
    card = function_body(text, "private var musicSourceCard: some View")
    if "canopyPlaybackToggles" not in card:
        return card
    return card + function_body(text, "private var canopyPlaybackToggles: some View")


def missing_rows(text):
    surface = playback_surface(text)
    missing = []
    for title, setting in ROWS:
        pattern = (
            r'GSToggleRow\(\s*symbol:\s*"[^"]+",\s*title:\s*"'
            + re.escape(title)
            + r'",\s*text:\s*"[^"]*",\s*isOn:\s*bool\('
            + re.escape(setting)
            + r"\)\s*\)"
        )
        if re.search(pattern, surface, re.S) is None:
            missing.append(setting)
    return missing


class CanopySettingsRows(unittest.TestCase):
    def test_music_source_card_draws_the_six_playback_toggles(self):
        text = PAGES.read_text(encoding="utf-8")
        self.assertEqual(missing_rows(text), [])
        surface = playback_surface(text)
        self.assertEqual(len(re.findall(r"\bGSToggleRow\(", surface)), 6)
        self.assertNotIn("\u2014", surface)
        self.assertNotIn("\u2013", surface)

    def test_a_card_that_drops_one_reader_is_rejected(self):
        text = PAGES.read_text(encoding="utf-8")
        dropped = text.replace("bool(LockScreenPlayerGate.settingID)", "bool(\"music.lockScreenPlayer\")", 1)
        self.assertEqual(missing_rows(dropped), ["LockScreenPlayerGate.settingID"])
