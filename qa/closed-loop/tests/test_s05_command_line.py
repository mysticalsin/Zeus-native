#!/usr/bin/env python3
"""S05-19. The command-line switch still says who else can run it."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class CommandLineDisclosureTests(unittest.TestCase):
    def test_detail_names_other_programs(self):
        page = (ROOT / "Sources/Zeus/Settings/GlanceSettingsPages.swift").read_text(encoding="utf-8")
        self.assertIn("Any program on this Mac running as you can run that command.", page)
