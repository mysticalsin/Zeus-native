"""An imported settings file cannot turn on the playback switches that start work."""
from pathlib import Path
import importlib.util
import unittest

ROOT = Path(__file__).resolve().parents[3]
STORE = ROOT / "Sources/Zeus/App/SettingsStore.swift"

HELD = (
    "music.systemNowPlaying",
    "music.receiverNames",
    "music.earbudOverlay",
    "music.focusName",
    "music.lockScreenPlayer",
)


def import_guard(text):
    start = text.index("static let neverEnabledByImport")
    block = text[start:text.index("]", start)]
    missing = [setting for setting in HELD if f'"{setting}"' not in block]
    if '"music.collapseOnPause"' in block:
        missing.append("music.collapseOnPause is a layout switch")
    return missing


def generator():
    spec = importlib.util.spec_from_file_location("settings_generator", ROOT / "scripts/gen-settings-catalog.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CanopyImportGuard(unittest.TestCase):
    def test_the_five_playback_switches_stay_out_of_an_import(self):
        text = STORE.read_text(encoding="utf-8")
        self.assertEqual(import_guard(text), [])
        self.assertIn('value == "true", Self.neverEnabledByImport.contains(id)', text)
        rows = {row[7]: row for row in generator().R}
        for setting in HELD:
            self.assertEqual(rows[setting][8], "toggle")
            self.assertEqual(rows[setting][10], "false")
            self.assertIn("An import never turns it on.", rows[setting][12])
        self.assertNotIn("An import never turns it on.", rows["music.collapseOnPause"][12])

    def test_a_guard_that_drops_one_switch_is_rejected(self):
        text = STORE.read_text(encoding="utf-8")
        dropped = text.replace('"music.lockScreenPlayer"', '"music.other"', 1)
        self.assertEqual(import_guard(dropped), ["music.lockScreenPlayer"])
