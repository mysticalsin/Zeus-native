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

    def test_harness_injects_reduced_motion_without_touching_defaults(self):
        cases = [
            ("Linux", {}),
            ("Darwin", {"GITHUB_ACTIONS": "false"}),
            ("Darwin", {"RUNNER_ENVIRONMENT": "self-hosted"}),
            ("Darwin", {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted"}),
        ]
        for system, environment in cases:
            with self.subTest(system=system, environment=environment):
                fixture = DefaultsFixture(True)
                observed = {}

                def native(arguments, observed=observed):
                    observed["arguments"] = list(arguments)
                    observed["reduced"] = os.environ.get("ZEUS_HARNESS_REDUCE_MOTION")
                    observed["marker"] = os.environ.get(profile.MARKER)
                    return 7

                with self.context(fixture, native, system=system, environment=environment) as (command, run, output):
                    self.assertEqual(profile.main(["--harness", "--jobs", "2"]), 7)
                    command.assert_not_called()
                    run.assert_called_once()
                    self.assertEqual(fixture.writes, [])
                    self.assertEqual(observed["arguments"], ["--jobs", "2"])
                    self.assertEqual(observed["reduced"], "1")
                    self.assertIsNone(observed["marker"])
                    self.assertNotIn("ZEUS_HARNESS_REDUCE_MOTION", os.environ)
                    text = output.getvalue()
                    self.assertNotIn(profile.DOMAIN, text)
                    self.assertNotIn("/usr/bin/defaults", text)
                    self.assertNotIn("defaults_untouched", text)

    def test_hosted_ci_path_does_not_use_the_harness_override(self):
        fixture = DefaultsFixture(True)

        def native(arguments):
            self.assertNotIn("ZEUS_HARNESS_REDUCE_MOTION", os.environ)
            self.assertEqual(os.environ[profile.MARKER], "1")
            self.assertIs(fixture.value, False)
            self.assertEqual(arguments, ["--jobs", "4"])
            return 0

        with self.context(fixture, native) as (command, _, output):
            self.assertEqual(profile.main(["--jobs", "4"]), 0)
            self.assertIs(fixture.value, True)
            self.assertEqual(fixture.writes, [False, True])
            for call in command.call_args_list:
                argv = call.args[0]
                self.assertEqual(argv[0], "/usr/bin/defaults")
                self.assertEqual(argv[2:4], [profile.DOMAIN, profile.KEY])
            text = output.getvalue()
            self.assertIn("original_reduce_motion=true", text)
            self.assertIn("restored=true", text)
            self.assertNotIn("ZEUS_HARNESS_REDUCE_MOTION", text)

    def test_host_applies_harness_reduced_motion_before_loading_tests(self):
        repo = Path(__file__).resolve().parents[3]
        host = (repo / "qa/native-app-host/NativeAppTestHost.swift").read_text()
        key = 'environment["ZEUS_HARNESS_REDUCE_MOTION"] == "1"'
        load = host.index("dlopen(args[2]")
        self.assertLess(host.index(key), load)
        marker = host.index(f'environment["{profile.MARKER}"] == "1"')
        workspace = host.index("!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion")
        self.assertLess(host.index(key), marker)
        self.assertLess(marker, workspace)
        self.assertLess(workspace, load)
        harness_body = host[host.index(key):marker]
        self.assertNotIn("NSWorkspace", harness_body)
        self.assertNotIn("defaults", harness_body)
        self.assertNotIn("universalaccess", harness_body)
        self.assertIn("harness reduced-motion profile applied before loading tests", harness_body)
        motion = (repo / "Sources/Zeus/App/Preferences.swift").read_text()
        reduced = motion[motion.index("static var reduced"):motion.index("static let feedbackDuration")]
        self.assertIn("ZEUS_HARNESS_REDUCE_MOTION", reduced)
        self.assertIn("#if DEBUG", reduced)
        self.assertIn("NSWorkspace.shared.accessibilityDisplayShouldReduceMotion", reduced)
        film = (repo / "Sources/Zeus/Onboarding/OnboardingVisuals.swift").read_text()
        self.assertIn("motionReduction || Motion.reduced", film)
        self.assertIn("let systemReduction = Motion.reduced", film)

    def test_reduce_motion_reads_go_through_motion_only(self):
        repo = Path(__file__).resolve().parents[3]
        allowed = repo / "Sources/Zeus/App/Preferences.swift"
        offenders = []
        for path in (repo / "Sources/Zeus").rglob("*.swift"):
            if path.resolve() == allowed.resolve():
                continue
            for number, line in enumerate(path.read_text().splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("//"):
                    continue
                if "accessibilityReduceMotion" in line or "accessibilityDisplayShouldReduceMotion" in line:
                    offenders.append(f"{path.relative_to(repo)}:{number}")
        self.assertEqual(offenders, [])

    def test_bundle_refuses_release_without_release_config(self):
        script = (Path(__file__).resolve().parents[3] / "scripts/bundle.sh").read_text()
        before_build = script.split("swift build", 1)[0]
        self.assertIn("Release builds must use CONFIG=release", before_build)
        self.assertIn('[ "$CONFIG" != release ]', before_build)

    def test_harness_does_not_claim_an_unchecked_defaults_result(self):
        fixture = DefaultsFixture(True)
        with self.context(fixture, lambda _: 0, system="Linux", environment={}) as (command, _, output):
            self.assertEqual(profile.main(["--harness"]), 0)
            text = output.getvalue()
            writes = [call.args[0] for call in command.call_args_list if "write" in call.args[0]]
            self.assertEqual(writes, [])
            if "defaults_untouched=true" in text:
                reads = [call.args[0] for call in command.call_args_list if call.args[0][1] in {"read", "read-type"}]
                self.assertGreaterEqual(len(reads), 2)
                self.assertNotIn("write", " ".join(" ".join(argv) for argv in (call.args[0] for call in command.call_args_list)))
            else:
                self.assertNotIn("defaults_untouched", text)

    def test_harness_override_requires_the_test_host_marker(self):
        repo = Path(__file__).resolve().parents[3]
        motion = (repo / "Sources/Zeus/App/Preferences.swift").read_text()
        reduced = motion[motion.index("static var reduced"):motion.index("static let feedbackDuration")]
        self.assertIn("ZEUS_MOTION_HARNESS_ACTIVE", reduced)
        self.assertIn("ZEUS_HARNESS_REDUCE_MOTION is ignored outside the test host", reduced)
        host = (repo / "qa/native-app-host/NativeAppTestHost.swift").read_text()
        self.assertLess(host.index('setenv("ZEUS_MOTION_HARNESS_ACTIVE", "1", 1)'), host.index("dlopen(args[2]"))

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
