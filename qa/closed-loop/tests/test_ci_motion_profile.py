"""Isolated transaction/host contracts; never read or change this machine's preferences."""
import contextlib
import io
import os
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ci_motion_profile as profile


class DefaultsFixture:
    def __init__(self, value=True, fault=None):
        self.value, self.fault = value, fault
        self.writes = []

    def run(self, command, **options):
        assert command[0] == "/usr/bin/defaults"
        assert command[2:4] == [profile.DOMAIN, profile.KEY]
        assert options["timeout"] == 5 and options["env"]["LC_ALL"] == "C"
        action = command[1]
        code, output = 0, ""
        if action == "read-type":
            if self.value is None:
                code = 1
            else:
                output = "Type is boolean" if type(self.value) is bool else "Type is string"
        elif action == "read":
            output = "1" if self.value else "0"
        else:
            assert action == "write" and command[4] == "-bool"
            value = command[5] == "true"
            self.writes.append(value)
            if not (self.fault == "ignored-setup" and len(self.writes) == 1
                    or self.fault == "ignored-restore" and len(self.writes) == 2):
                self.value = value
            if (self.fault == "failed-setup" and len(self.writes) == 1
                    or self.fault == "failed-restore" and len(self.writes) == 2):
                code = 1
        return SimpleNamespace(returncode=code, stdout=output, stderr="PRIVATE_DIAGNOSTIC")


class CIMotionProfileTests(unittest.TestCase):
    @contextlib.contextmanager
    def context(self, fixture, native, *, system="Darwin", environment=None):
        environment = {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted", **(environment or {})}
        with patch.dict(os.environ, environment, clear=True), patch.object(profile.platform, "system", return_value=system), \
             patch.object(profile.subprocess, "run", side_effect=fixture.run) as command, \
             patch.object(profile, "run_native", side_effect=native) as run, \
             patch.object(profile.signal, "signal"), contextlib.redirect_stdout(io.StringIO()) as output:
            yield command, run, output

    def test_local_self_hosted_and_non_mac_runs_never_touch_preferences(self):
        for system, environment in [("Linux", {}), ("Darwin", {"GITHUB_ACTIONS": "false"}),
                                    ("Darwin", {"RUNNER_ENVIRONMENT": "self-hosted"})]:
            with self.subTest(system=system, environment=environment):
                with self.context(DefaultsFixture(), lambda _: 0, system=system, environment=environment) as (command, run, _):
                    self.assertEqual(profile.main([]), 1)
                    command.assert_not_called()
                    run.assert_not_called()

    def test_original_boolean_marker_and_native_exit_are_preserved(self):
        for initial in (False, True):
            for native_code in (0, 9):
                fixture = DefaultsFixture(initial)
                def native(arguments):
                    self.assertFalse(fixture.value)
                    self.assertEqual(os.environ[profile.MARKER], "1")
                    self.assertEqual(arguments, ["--jobs", "4"])
                    return native_code
                with self.context(fixture, native, environment={profile.MARKER: "original"}):
                    self.assertEqual(profile.main(["--jobs", "4"]), native_code)
                    self.assertIs(fixture.value, initial)
                    self.assertEqual(os.environ[profile.MARKER], "original")
                    self.assertEqual(fixture.writes, [False, initial])

    def test_absent_nonboolean_and_failed_snapshot_are_not_modified(self):
        for value in (None, "unknown"):
            fixture = DefaultsFixture(value)
            with self.context(fixture, lambda _: 0) as (_, run, output):
                self.assertEqual(profile.main([]), 1)
                self.assertEqual(fixture.writes, [])
                run.assert_not_called()
                self.assertNotIn("PRIVATE_DIAGNOSTIC", output.getvalue())
        fixture = DefaultsFixture()
        with self.context(fixture, lambda _: 0) as (_, run, _):
            with patch.object(profile.subprocess, "run", side_effect=profile.subprocess.TimeoutExpired("defaults", 5)):
                self.assertEqual(profile.main([]), 1)
            self.assertEqual(fixture.writes, [])
            run.assert_not_called()

    def test_failed_or_ignored_setup_restores_before_returning_failure(self):
        for fault in ("failed-setup", "ignored-setup"):
            fixture = DefaultsFixture(True, fault)
            with self.context(fixture, lambda _: 0) as (_, run, _):
                self.assertEqual(profile.main([]), 1)
                self.assertTrue(fixture.value)
                self.assertEqual(fixture.writes, [False, True])
                self.assertNotIn(profile.MARKER, os.environ)
                run.assert_not_called()

    def test_native_exception_and_interruption_still_restore(self):
        for error, code in [(RuntimeError("synthetic"), 1), (KeyboardInterrupt(), 130), (SystemExit(0), 1)]:
            fixture = DefaultsFixture()
            with self.context(fixture, error):
                self.assertEqual(profile.main([]), code)
                self.assertTrue(fixture.value)
                self.assertNotIn(profile.MARKER, os.environ)

    def test_failed_restore_never_turns_native_success_into_job_success(self):
        for fault in ("failed-restore", "ignored-restore"):
            for native_code in (0, 9):
                fixture = DefaultsFixture(True, fault)
                with self.context(fixture, lambda _: native_code) as (_, _, output):
                    self.assertEqual(profile.main([]), native_code or 1)
                    self.assertIn("restored=false", output.getvalue())

    def test_fresh_host_requires_real_normal_motion_before_loading_tests(self):
        repo = Path(__file__).resolve().parents[3]
        host = (repo / "qa/native-app-host/NativeAppTestHost.swift").read_text()
        self.assertIn(f'environment["{profile.MARKER}"] == "1"', host)
        self.assertIn('environment["RUNNER_ENVIRONMENT"] == "github-hosted"', host)
        self.assertIn("!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion", host)
        self.assertLess(host.index("!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion"), host.index("dlopen(args[2]"))
        workflow = (repo / ".github/workflows/build.yml").read_text()
        self.assertIn("python3 qa/closed-loop/ci_motion_profile.py --output", workflow)


if __name__ == "__main__":
    unittest.main()
