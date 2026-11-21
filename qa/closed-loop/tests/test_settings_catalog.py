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
                    'general.showInScreenSharing', 'present.physicalPointer', 'explanation.enabled',
                    'tiling.enabled', 'fling.enabled', 'todo.microsoftLocal'):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                module = generator()
                index = next(i for i, row in enumerate(module.R) if row[7] == key)
                changed = list(module.R[index]); changed[10] = 'true'; module.R[index] = tuple(changed)
                for writer in (module.write_swift, module.write_md):
                    output = Path(directory) / 'must-not-exist'
                    with self.assertRaisesRegex(ValueError, 'explicit opt-in'):
                        writer(output)
                    self.assertFalse(output.exists())

    def test_see_screen_row_is_live_on_by_default_and_drawing_stays_an_opt_in(self):
        module = generator()
        rows = {row[7]: row for row in module.R}
        see, draw = rows['talk.seeScreen'], rows['talk.drawOnScreen']
        self.assertEqual((see[0], see[8], see[10], see[11]), ('voice', 'toggle', 'true', 'live'))
        self.assertEqual((draw[8], draw[10]), ('toggle', 'false'))

    def test_tiling_rows_are_live_and_use_our_own_wording(self):
        module = generator()
        rows = [row for row in module.R if row[0] == 'tiling']
        self.assertEqual([row[7] for row in rows], ['tiling.enabled', 'tiling.keyBase', 'tiling.innerGap', 'tiling.outerGap',
                                                    'tiling.splitRatio', 'tiling.focusBorder', 'tiling.excludedApps'])
        self.assertEqual(module.SECTION_TITLES['tiling'], 'Tiling')
        for row in rows:
            with self.subTest(key=row[7]):
                self.assertEqual(row[11], 'live')
                # No reference app to study: the reference default is '-' and the control names the row's own kind.
                self.assertEqual(row[4], '-')
                self.assertEqual(row[6], 'missing')
                self.assertTrue(row[12].startswith('Zeus addition.'))

    def test_fling_rows_exist_in_the_shelf_section_and_start_off(self):
        module = generator()
        rows = {row[7]: row for row in module.R if row[0] == 'shelf'}
        self.assertEqual(list(rows), ['fling.enabled', 'fling.receiveInBackground', 'fling.deviceName', 'fling.visibility',
                                      'fling.autoAcceptPaired', 'fling.saveMode', 'fling.papers', 'fling.flickSensitivity',
                                      'fling.openLinks', 'fling.pairedMacs'])
        self.assertEqual(module.SECTION_TITLES['shelf'], 'Shelf')
        defaults = {key: row[10] for key, row in rows.items()}
        self.assertEqual(defaults['fling.enabled'], 'false')
        self.assertEqual(defaults['fling.papers'], 'false')
        self.assertEqual(defaults['fling.receiveInBackground'], 'true')
        self.assertEqual(defaults['fling.openLinks'], 'true')
        self.assertEqual(defaults['fling.autoAcceptPaired'], 'true')
        self.assertEqual(defaults['fling.visibility'], 'Everyone nearby')
        self.assertEqual(rows['fling.visibility'][9], ['Everyone nearby', 'Paired only', 'Off'])
        self.assertEqual(defaults['fling.saveMode'], 'Downloads/Fling')
        self.assertEqual(rows['fling.saveMode'][9], ['Downloads/Fling', 'Clipboard', 'Ask each time'])
        self.assertEqual(defaults['fling.flickSensitivity'], 'Normal')
        self.assertEqual(rows['fling.flickSensitivity'][9], ['Low', 'Normal', 'High'])
        light = next(row for row in module.R if row[7] == 'lights.fling')
        self.assertEqual((light[0], light[8], light[10]), ('appearance', 'toggle', 'true'))

    def test_tiling_enabled_default_cannot_be_removed_or_made_true(self):
        module = generator()
        index = next(i for i, row in enumerate(module.R) if row[7] == 'tiling.enabled')
        module.R.pop(index)
        with self.assertRaisesRegex(ValueError, 'tiling.enabled must remain an explicit opt-in'):
            module.validate_table()

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
