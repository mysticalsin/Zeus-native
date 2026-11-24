"""Source guards for VoiceOver labels, keyboard focus, and Reduce Motion.

These read the current sources. They do not compile the Mac app, drive VoiceOver,
or claim a device pass. The GitHub macOS `app` job still has to build and run the suites.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def source(relative):
    return (ROOT / relative).read_text()


class ConnectionControlSourceTests(unittest.TestCase):
    def test_connection_buttons_name_the_provider(self):
        page = source("Sources/Zeus/Settings/GSAIConnectionsPage.swift")
        style = source("Sources/Zeus/Settings/GlanceSettingsStyle.swift")
        toggle = style[style.index("struct GSToggleStyle"):style.index("struct GSPopup")]
        button = style[style.index("struct GSButtonStyle"):style.index("extension View")]
        self.assertIn("ConnectionControlSpeech.primary", page)
        self.assertIn("ConnectionControlSpeech.status", page)
        self.assertIn("ConnectionControlSpeech.field", page)
        self.assertIn("MotionEffect", toggle)
        self.assertNotIn(".spring(", toggle)
        self.assertNotIn("Motion.reduced", toggle)
        self.assertNotIn("Motion.reduced", button)
        self.assertIn("isFocused", button)
        self.assertIn("accessibilityHint", page)

    def test_voice_orb_reduce_motion_is_immediate_and_named(self):
        orb = source("Sources/Zeus/Voice/ThinkingOrb.swift")
        ring = source("Sources/Zeus/Voice/VoiceRingView.swift")
        self.assertIn("ThinkingOrbSpeech.reducedDiscOpacity", orb)
        self.assertIn("ThinkingOrbSpeech.label", orb)
        self.assertNotIn("accessibilityHidden(true)", orb)
        self.assertNotIn("TickingView", orb)
        self.assertNotIn(".easeInOut", ring)
        self.assertIn("state.accessibilityLabel", ring)
        self.assertIn("VoiceRingAccessibility.value", ring)
        self.assertIn("focusable(VoiceRingAccessibility.takesKeyboardFocus)", ring)
