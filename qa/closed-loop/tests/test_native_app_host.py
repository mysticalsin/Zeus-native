"""AppKit launcher and evidence-contract tests, not native UI acceptance."""
import copy
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import native_app_host as host
import native_evidence as evidence
import trusted_ax
from contracts import Invalid, digest
import test_native_evidence as fixtures


class NativeAppHostTests(unittest.TestCase):
    def definition(self, suite="OwnedWindowEventDriverTests"):
        return {"kind": "native-fixture", "suite": suite, "file": "Tests/ZeusAppTests/OwnedWindowEventDriver.swift"}

    def test_only_owned_journeys_use_exact_host_and_recorded_bundle(self):
        for suite in sorted(host.SUITES - host.TRUSTED_SUITES):
            definition = self.definition(suite)
            command = evidence.run_command([definition], 4, "/evidence", "native-case", "/compiled/source")
            self.assertEqual(command, [str(host.executable("/evidence", "native-case")),
                "--test-bundle-path", "/compiled/source/.build/debug/ZeusPackageTests.xctest/Contents/MacOS/ZeusPackageTests",
                "--filter", "^ZeusAppTests\\." + suite + "/", "--event-stream-output-path",
                "/evidence/native-case/events.jsonl", "--event-stream-version", "0"])
        regular = self.definition("OtherTests")
        self.assertEqual(evidence.run_command([regular], 4, "/evidence", "ordinary")[:5],
                         ["swift", "test", "--skip-build", "--jobs", "4"])
        with self.assertRaises(Invalid):
            evidence.run_command([self.definition(), regular], 4, "/evidence", "mixed")

    def test_packaging_preserves_compiled_bytes_and_has_no_capture_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, output, platform = root / "repo", root / "evidence", root / "platform"
            binary = repo / ".build/debug/zeus-native-test-host"
            tests = host.bundle_binary(repo)
            for path in (binary, tests):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"synthetic compiled bytes")
                path.chmod(0o700)
            for suffix in ("Developer/Library/Frameworks", "Developer/Library/PrivateFrameworks", "Developer/usr/lib"):
                (platform / suffix).mkdir(parents=True)
            with patch.object(host.subprocess, "run", return_value=SimpleNamespace(stdout=str(platform) + "\n")) as probe:
                environment = host.prepare(output, "native-case", repo)
            probe.assert_called_once_with(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-platform-path"],
                capture_output=True, text=True, check=True, timeout=10)
            copied = host.executable(output, "native-case")
            self.assertEqual(copied.read_bytes(), binary.read_bytes())
            self.assertEqual(plistlib.loads((copied.parent.parent / "Info.plist").read_bytes()), host.INFO)
            self.assertIn(str(platform / "Developer/Library/PrivateFrameworks"), environment["DYLD_FRAMEWORK_PATH"])
            inputs = json.loads(host.inputs_path(output, "native-case").read_text())
            self.assertEqual(inputs, {"schema_version": 1, "test_bundle": {
                "path": str(tests), "resolved_path": str(tests.resolve()), "sha256": digest(tests.read_bytes())},
                "selected_platform": str(platform)})
            self.assertNotIn("environment", inputs)
            with self.assertRaises(FileExistsError):
                host.prepare(output, "native-case", repo)

    def test_provenance_rejects_outside_build_bundle_and_tracks_compiled_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tests = host.bundle_binary(root)
            tests.parent.mkdir(parents=True)
            foreign = root / "foreign"
            foreign.write_bytes(b"foreign binary")
            foreign.chmod(0o700)
            tests.symlink_to(foreign)
            with self.assertRaisesRegex(Invalid, "redirected"):
                host.input_provenance(root, {"platform": "/selected/platform"})
            tests.unlink()
            tests.write_bytes(b"first synthetic bundle")
            tests.chmod(0o700)
            before = host.input_provenance(root, {"platform": "/selected/platform"})
            tests.write_bytes(b"changed synthetic bundle")
            self.assertNotEqual(before, host.input_provenance(root, {"platform": "/selected/platform"}))

    def test_host_receipt_cannot_replace_complete_qualified_execution(self):
        fixture = fixtures.NativeEventEvidenceTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        fixture.source = fixture.repo / "Tests/ZeusAppTests/OwnedWindowEventDriver.swift"
        fixture.source.parent.mkdir(parents=True)
        fixture.source.write_text("import Testing\nstruct OwnedWindowEventDriverTests {\n    @Test func example() {}\n}\n")
        fixture.suite = "ZeusAppTests.OwnedWindowEventDriverTests"
        fixture.ident = fixture.suite + "/example()/OwnedWindowEventDriver.swift:3:6"
        fixture.payload.update(id=fixture.ident, sourceLocation={"_filePath": str(fixture.source),
            "fileID": "ZeusAppTests/OwnedWindowEventDriver.swift", "line": 3, "column": 6})
        fixture.declarations[0]["payload"]["id"] = fixture.suite
        fixture.definitions = [self.definition()]
        compiled = fixture.compiled()
        output = fixture.repo / "evidence"
        ident = "native-owned"
        binary = host.executable(output, ident)
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"synthetic host fixture")
        info = binary.parent.parent / "Info.plist"
        info.write_bytes(plistlib.dumps(host.INFO))
        folder = output / ident
        log, events = folder / "test.log", folder / "events.jsonl"
        log.write_text("✔ Test example() passed after 0.1 seconds.\n✔ Test run with 1 test in 1 suite passed after 0.1 seconds.\n")
        def write_events(rows):
            events.write_text("".join(json.dumps(row) + "\n" for row in rows))
        write_events(fixture.events())
        metrics = evidence.execution(events, compiled, fixture.definitions, fixture.repo)
        row = {"id": ident, "status": "passed", "exit_code": 0, **metrics, "passed_functions": ["example"],
               "command": evidence.run_command(fixture.definitions, 4, output, ident, fixture.repo)}
        def refresh():
            row["artifacts"] = [{"path": str(path.relative_to(output)), "sha256": digest(path.read_bytes())}
                                for path in (log, events, binary, info)]
        def validate():
            return evidence.validate_run_receipt(row, output, compiled, fixture.definitions, 4,
                                                 str(fixture.repo), str(output), fixture.repo)
        refresh()
        self.assertEqual(validate()["tests"], 1)
        write_events(fixture.events()[:-1])
        refresh()
        with self.assertRaisesRegex(Invalid, "incomplete"):
            validate()
        write_events(fixture.events())
        refresh()
        changed = copy.deepcopy(row["command"])
        row["command"][2] = "/other/compiled/bundle"
        with self.assertRaisesRegex(Invalid, "command changed"):
            validate()
        row["command"] = changed
        row["artifacts"] = row["artifacts"][:-1]
        with self.assertRaisesRegex(Invalid, "host artifacts"):
            validate()


class TrustedAXRunnerTests(unittest.TestCase):
    SUITE = "ScribeTrustedAccessibilityJourneyTests"
    TEST = "ZeusAppTests." + SUITE + "/" + trusted_ax.REQUIRED_FUNCTION + "()/ScribeComponentJourneyTests.swift:1:1"

    def definition(self, kind):
        return {"kind": kind, "suite": self.SUITE, "file": "Tests/ZeusAppTests/ScribeComponentJourneyTests.swift"}

    def events(self, rows):
        folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, folder, True)
        path = folder / "events.jsonl"
        path.write_text("".join(json.dumps({"version": 0, **row}) + "\n" for row in rows))
        return path

    def clean(self, ident=None, end="pass", run_end="pass"):
        ident = ident or self.TEST
        mark = lambda symbol: {"messages": [{"symbol": symbol}]}
        return [{"kind": "test", "payload": {"kind": "function", "id": ident}},
                {"kind": "event", "payload": {"kind": "runStarted"}},
                {"kind": "event", "payload": {"kind": "testStarted", "testID": ident}},
                {"kind": "event", "payload": {"kind": "testEnded", "testID": ident, **mark(end)}},
                {"kind": "event", "payload": {"kind": "runEnded", **mark(run_end)}}]

    def test_ci_never_selects_the_trusted_suite_even_though_the_host_can_launch_it(self):
        self.assertIn(self.SUITE, host.SUITES)
        self.assertFalse(host.selected([self.definition("trusted-native-fixture")]))
        self.assertFalse(host.selected([self.definition("native-fixture")]))
        self.assertNotIn("trusted-native-fixture", evidence.NATIVE_KINDS)
        swift = (Path(__file__).resolve().parents[3] / "qa/native-app-host/NativeAppTestHost.swift").read_text()
        self.assertIn(trusted_ax.FILTER.replace("\\", "\\\\"), swift)

    def test_command_uses_exact_filter_and_absolute_event_stream(self):
        argv = trusted_ax.command(Path("/h"), Path("/t"), Path("/e/events.jsonl"))
        self.assertEqual(argv, ["/h", "--test-bundle-path", "/t", "--filter", "^ZeusAppTests\\." + self.SUITE + "/",
                                "--event-stream-output-path", "/e/events.jsonl", "--event-stream-version", "0"])

    def test_clean_stream_passes_and_missing_stream_never_does(self):
        problems, ids = trusted_ax.validate_events(self.events(self.clean()))
        self.assertEqual((problems, ids), ([], [self.TEST]))
        problems, ids = trusted_ax.validate_events(Path(tempfile.gettempdir()) / "absent-events.jsonl")
        self.assertTrue(problems and not ids)

    def test_stream_defects_never_pass(self):
        base = self.clean()
        cases = {"no run end": base[:-1], "no test end": base[:3] + base[4:],
                 "failed end": self.clean(end="fail"), "failed run": self.clean(run_end="fail"),
                 "wrong suite": self.clean(ident="ZeusAppTests.OtherTests/x()/F.swift:1:1"),
                 "issue": base[:3] + [{"kind": "event", "payload": {"kind": "issueRecorded", "testID": self.TEST}}] + base[3:]}
        for name, rows in cases.items():
            with self.subTest(name):
                problems, _ = trusted_ax.validate_events(self.events(rows))
                self.assertTrue(problems, name)

    def test_runner_refuses_ci_and_non_macos(self):
        with patch.dict(trusted_ax.os.environ, {"GITHUB_ACTIONS": "true"}), \
                patch.object(trusted_ax.platform, "system", return_value="Darwin"):
            with self.assertRaisesRegex(Invalid, "never runs in CI"):
                trusted_ax.require_local_mac()
        with patch.object(trusted_ax.platform, "system", return_value="Linux"):
            with self.assertRaisesRegex(Invalid, "requires macOS"):
                trusted_ax.require_local_mac()


if __name__ == "__main__":
    unittest.main()
