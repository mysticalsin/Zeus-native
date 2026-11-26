"""The middle bar and its animation share one hue.

The numbers live in ZeusCore. This reads that source and the two views that paint it,
so the check runs where Swift is absent.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
TONE = ROOT / "Sources/ZeusCore/Voice/MiddleBarTone.swift"
TOKENS = ROOT / "Sources/ZeusCore/ThemeTokens.swift"
BEAM = ROOT / "Sources/Zeus/Voice/AssistantBeamView.swift"
BAR = ROOT / "Sources/Zeus/TopBar/RecordingFeedbackView.swift"
WING = ROOT / "Sources/Zeus/TopBar/TopBarViews.swift"


def hue_turns(red, green, blue):
    max_channel = max(red, green, blue)
    min_channel = min(red, green, blue)
    delta = max_channel - min_channel
    if delta <= 1e-8:
        return 0.0
    if max_channel == red:
        sector = (green - blue) / delta
        if sector < 0:
            sector += 6
    elif max_channel == green:
        sector = (blue - red) / delta + 2
    else:
        sector = (red - green) / delta + 4
    return sector / 6


def hue_distance(first, second):
    delta = abs(hue_turns(*first) - hue_turns(*second))
    return min(delta, 1 - delta)


def mix(color, white=0, black=0):
    lift = min(1, max(0, white))
    shade = min(1, max(0, black))

    def channel(value):
        return (value + (1 - value) * lift) * (1 - shade)

    return tuple(channel(value) for value in color)


def rgb(hex_value):
    return ((hex_value >> 16) & 0xFF) / 255, ((hex_value >> 8) & 0xFF) / 255, (hex_value & 0xFF) / 255


class MiddleBarToneTests(unittest.TestCase):
    def test_shades_keep_the_bar_hue_and_leave_mascot_gold(self):
        tokens = TOKENS.read_text()
        purple = int(re.search(r"zeusPurple: UInt32 = (0x[0-9A-Fa-f]+)", tokens).group(1), 16)
        gold = int(re.search(r"lightningGold: UInt32 = (0x[0-9A-Fa-f]+)", tokens).group(1), 16)
        source = TONE.read_text()
        self.assertIn("RGB(hex: ZeusThemeTokens.zeusPurple)", source)
        body = source.split("public static let shades", 1)[1].split("]", 1)[1].split("]", 1)[0]
        shades = re.findall(r"mix\(bar, (white|black): ([0-9.]+)\)", body)
        self.assertEqual(len(shades), 6)
        self.assertIn("bar,", body)
        bar = rgb(purple)
        painted = [bar]
        for kind, amount in shades:
            painted.append(mix(bar, **{kind: float(amount)}))
        self.assertEqual(len(painted), 7)
        for shade in painted:
            self.assertLess(hue_distance(shade, bar), 1e-9)
            self.assertGreater(hue_distance(shade, rgb(gold)), 0.2)

    def test_views_paint_that_tone(self):
        beam = BEAM.read_text()
        bar = BAR.read_text()
        wing = WING.read_text()
        self.assertIn("MiddleBarTone.shades", beam)
        self.assertIn("MiddleBarTone.bar", beam)
        self.assertNotIn("hueRotation", beam)
        self.assertNotIn("0x28C8BE", beam)
        self.assertNotIn("Theme.danger", beam)
        self.assertNotIn("Theme.leaf", beam)
        self.assertNotIn("Theme.sky", beam)
        self.assertIn("MiddleBarTone.bar", bar)
        self.assertIn("MiddleBarTone.shades", bar)
        self.assertIn("Color(middleBar: MiddleBarTone.bar)", wing)
