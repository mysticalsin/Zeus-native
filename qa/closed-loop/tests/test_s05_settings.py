#!/usr/bin/env python3
"""S05 settings coherence. Reads source. Does not launch the app."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def text(path):
    return (ROOT / path).read_text(encoding="utf-8")


class S05SettingsTests(unittest.TestCase):
    def test_talk_screenshots_default_off(self):
        feature = text("Sources/ZeusCore/FeatureSettings.swift")
        self.assertIn('bool("talk.seeScreen", default: false', feature)
        catalog = text("scripts/gen-settings-catalog.py")
        row = next(line for line in catalog.splitlines() if "'talk.seeScreen'" in line)
        self.assertIn("'false'", row)
        self.assertNotIn("'true','live'", row)
        voice = text("Sources/Zeus/Settings/GlanceSettingsPages.swift")
        self.assertIn('boolBinding("talk.seeScreen")', voice)

    def test_quick_todo_does_not_use_the_polyglot_chord(self):
        extra = text("Sources/Zeus/App/ExtraPreferences.swift")
        self.assertIn("?? .controlCommandZ", extra)
        self.assertNotIn("?? .controlOptionT", extra)
        pages = text("Sources/Zeus/Settings/GlanceSettingsPages.swift")
        self.assertIn("Quick to-do", pages)
        self.assertIn("quickTodo", pages)

    def test_pointing_has_a_settings_card_and_an_honest_note(self):
        pages = text("Sources/Zeus/Settings/GlanceSettingsPages.swift")
        self.assertIn('boolBinding("pointing.enabled")', pages)
        self.assertIn('stringBinding("pointing.shortcut")', pages)
        note = text("scripts/gen-settings-catalog.py")
        row = next(line for line in note.splitlines() if "'pointing.shortcut'" in line)
        self.assertIn("second talk key", row)
        self.assertNotIn("Pick Right Option or Fn for a separate pointing turn", row)

    def test_murmur_is_the_visible_name(self):
        window = text("Sources/Zeus/Settings/SettingsWindow.swift")
        self.assertIn('case .murmure: "Murmur"', window)
        self.assertNotIn('case .murmure: "Murmure"', window)
        layout = text("Sources/ZeusCore/TopBar/TopBarLayout.swift")
        self.assertIn('case .dictation: "Murmur"', layout)

    def test_top_bar_is_the_visible_name_for_the_strip(self):
        pages = text("Sources/Zeus/Settings/GlanceSettingsPages.swift")
        self.assertIn('title: "Open the top bar on"', pages)
        self.assertIn('title: "Hide the top bar automatically"', pages)
        self.assertIn('title: "Top bar background"', pages)
        self.assertNotIn('title: "Island background"', pages)
        self.assertNotIn('title: "Open the notch on"', pages)

    def test_screen_share_switch_appears_once_in_settings(self):
        pages = text("Sources/Zeus/Settings/GlanceSettingsPages.swift")
        self.assertEqual(pages.count('bool("general.showInScreenSharing")') + pages.count("showInSharingKey"), 1)

    def test_dictation_sound_switch_is_single(self):
        pages = text("Sources/Zeus/Settings/GlanceSettingsPages.swift")
        self.assertNotIn('title: "Play dictation sounds"', pages)
        dictation = text("Sources/Zeus/Settings/GSDictationPage.swift")
        self.assertEqual(dictation.count("settings.sounds"), 1)

    def test_answer_keys_are_named(self):
        pages = text("Sources/Zeus/Settings/GlanceSettingsPages.swift")
        self.assertIn("Control-Option Y", pages)
        self.assertIn("Return opens", pages)

    def test_murmur_and_right_option_are_labeled(self):
        pages = text("Sources/Zeus/Settings/GlanceSettingsPages.swift")
        self.assertIn("Right Command", pages)
        self.assertIn("Hold Right Option to talk to Zeus", pages)

    def test_pointer_controls_use_different_names(self):
        buddy = text("Sources/ZeusCore/BuddyVisibility.swift")
        self.assertIn('case .onCall: "Only when called"', buddy)
        self.assertNotIn("When I call him", buddy)
        panel = text("Sources/Zeus/App/PanelView.swift")
        self.assertIn("Dictation pill follows the pointer", panel)

    def test_sound_picker_hides_internal_style_names(self):
        pages = text("Sources/Zeus/Settings/GlanceSettingsPages.swift")
        self.assertIn("Soft pulse", pages)
        self.assertNotIn("Weard Permission", pages)
        self.assertIn("Solid panel", pages)

    def test_destructive_rows_confirm(self):
        voices = text("Sources/Zeus/Settings/GSSpeakerRecognitionCard.swift")
        self.assertIn("confirmingVoice", voices)
        trusted = text("Sources/Zeus/Settings/GSAgentHubCards.swift")
        self.assertIn("confirmingClear", trusted)
        shelf = text("Sources/Zeus/Settings/GSShelfPage.swift")
        self.assertIn("confirmingMac", shelf)
        insomnia = text("Sources/Zeus/Settings/GSInsomniaPage.swift")
        self.assertIn("confirmingRemove", insomnia)
        self.assertNotIn("pmset", insomnia)

    def test_polyglot_hint_does_not_promise_a_wake_phrase_that_is_off(self):
        page = text("Sources/Zeus/Settings/GSPolyglotPage.swift")
        self.assertNotIn("Hey Zeus, translate", page)

    def test_fling_card_uses_the_switch_words(self):
        shelf = text("Sources/Zeus/Settings/GSShelfPage.swift")
        self.assertNotIn('GSCard("Fling")', shelf)
        menu = text("Sources/Zeus/Stickies/ShelfBrainMenu.swift")
        self.assertNotIn('Menu("Fling to")', menu)
