#!/usr/bin/env python3
"""Regression guards for generation of capture/input opt-ins; no app launch."""
from pathlib import Path
import contextlib
import importlib.util
import io
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


def generator():
    spec = importlib.util.spec_from_file_location('settings_generator', ROOT / 'scripts/gen-settings-catalog.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SettingsGenerationTests(unittest.TestCase):
    def test_catalog_and_inventory_match_the_generator(self):
        module = generator()
        with tempfile.TemporaryDirectory() as directory:
            catalog, inventory = Path(directory) / 'SettingsCatalog.swift', Path(directory) / 'inventory.md'
            module.write_swift(catalog)
            with contextlib.redirect_stdout(io.StringIO()):
                module.write_md(inventory)
            self.assertEqual(catalog.read_bytes(), (ROOT / 'Sources/Zeus/App/SettingsCatalog.swift').read_bytes())
            self.assertEqual(inventory.read_bytes(), (ROOT / 'docs/settings-inventory.md').read_bytes())

    def test_capture_and_input_default_regressions_fail_before_any_output(self):
        for key in ('voice.answers', 'voice.heyZeus', 'wake.ignoreMicConflicts', 'lights.liveSpectrum',
                    'general.showInScreenSharing', 'present.physicalPointer', 'explanation.enabled'):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                module = generator()
                index = next(i for i, row in enumerate(module.R) if row[7] == key)
                changed = list(module.R[index]); changed[10] = 'true'; module.R[index] = tuple(changed)
                for writer in (module.write_swift, module.write_md):
                    output = Path(directory) / 'must-not-exist'
                    with self.assertRaisesRegex(ValueError, 'explicit opt-in'):
                        writer(output)
                    self.assertFalse(output.exists())

    def test_debug_mic_bypass_cannot_be_exposed_or_silently_removed(self):
        module = generator()
        index = next(i for i, row in enumerate(module.R) if row[7] == 'wake.ignoreMicConflicts')
        changed = list(module.R[index]); changed[11] = 'live'; module.R[index] = tuple(changed)
        with self.assertRaisesRegex(ValueError, 'hidden from release'):
            module.validate_table()
        module.R.pop(index)
        with self.assertRaisesRegex(ValueError, 'explicit opt-in'):
            module.validate_table()

    def test_later_duplicate_cannot_conceal_the_emitted_unsafe_default(self):
        module = generator()
        index = next(i for i, row in enumerate(module.R) if row[7] == 'voice.heyZeus')
        module.R.append(module.R[index])
        changed = list(module.R[index]); changed[10] = 'true'; module.R[index] = tuple(changed)
        with self.assertRaisesRegex(ValueError, 'explicit opt-in'):
            module.validate_table()


if __name__ == '__main__':
    unittest.main()
