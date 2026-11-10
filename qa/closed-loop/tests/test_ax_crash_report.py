"""Synthetic IPS and receipt fixtures only: no Mac crash, capture, or debugger."""
import copy
from contextlib import redirect_stdout
from datetime import datetime, timezone
import json
import io
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ax_crash_report as ax
from contracts import Invalid, digest, source_snapshot


class AXCrashReportTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.repo, self.evidence = self.root / "repo", self.root / "native-evidence"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        subprocess.run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                        "commit", "--allow-empty", "-qm", "synthetic receipt fixture"], cwd=self.repo, check=True)
        self.sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.repo).decode().strip()
        environment = patch.dict(os.environ, {"ZEUS_TESTED_SHA": self.sha, "ZEUS_HEAD_SHA": self.sha})
        environment.start()
        self.addCleanup(environment.stop)
        (self.repo / ".gitignore").write_text(".build/\n")
        self.source = self.repo / ax.DEFINITION["file"]
        self.source.parent.mkdir(parents=True)
        self.source.write_text("import Testing\nstruct ScribeAccessibilityJourneyTests {\n    @Test func example() {}\n}\n")
        (self.repo / "qa").mkdir()
        (self.repo / "qa/feature-map.json").write_text(json.dumps({"checks": [ax.DEFINITION]}))
        (self.repo / "qa/regressions.json").write_text('{"regressions": []}')
        self.bundle = ax.host.bundle_binary(self.repo)
        self.bundle.parent.mkdir(parents=True)
        self.bundle.write_bytes(b"synthetic compiled bundle, never executable code")
        self.bundle.chmod(0o700)
        self.binary = ax.host.executable(self.evidence, ax.IDENT)
        self.binary.parent.mkdir(parents=True)
        self.binary.write_bytes(b"synthetic host, never executable code")
        self.binary.chmod(0o700)
        info = self.binary.parent.parent / "Info.plist"
        info.write_bytes(plistlib.dumps(ax.host.INFO))
        inputs = ax.host.inputs_path(self.evidence, ax.IDENT)
        inputs.write_text(json.dumps(ax.host.input_provenance(self.repo, {"platform": "/selected/Xcode.platform"})))
        self.started = 1794304800.0
        self.identity = {"pid": 4242, "started": self.iso(self.started), "executable": str(self.binary)}
        self.log = self.evidence / ax.IDENT / "test.log"
        self.log.write_text(ax.IDENTITY_PREFIX + json.dumps(self.identity) + "\nOriginal synthetic failure\n")
        events = self.evidence / ax.IDENT / "events.jsonl"
        events.write_text('{"partial": "synthetic interrupted event stream"}\n')
        for name in ("native-build", "native-discovery"):
            (self.evidence / name).mkdir()
        (self.evidence / "native-build/build.log").write_text("Build complete! (0.1s)\n")
        (self.evidence / "native-discovery/test.log").write_text("synthetic compiled discovery\n")
        suite = "ZeusAppTests.ScribeAccessibilityJourneyTests"
        declarations = [{"kind": "test", "version": 0, "payload": {"kind": "suite", "id": suite}},
            {"kind": "test", "version": 0, "payload": {"kind": "function", "name": "example()",
             "id": suite + "/example()/ScribeComponentJourneyTests.swift:3:6", "isParameterized": False,
             "sourceLocation": {"_filePath": str(self.source), "fileID": "ZeusAppTests/ScribeComponentJourneyTests.swift",
                                "line": 3, "column": 6}}}]
        (self.evidence / "native-discovery/events.jsonl").write_text("".join(json.dumps(row) + "\n" for row in declarations))
        snapshot = source_snapshot(self.repo, self.evidence)
        (self.evidence / "source-manifest.json").write_text(json.dumps(snapshot))
        common = {"status": "passed", "exit_code": 0, "source_snapshot_sha256": snapshot["sha256"], "duration_seconds": 0.1}
        self.row = {"id": ax.IDENT, "kind": "native-fixture", "status": "failed", "exit_code": -5,
                    "duration_seconds": 5.5, "command": ax.native.run_command([ax.DEFINITION], 2, self.evidence, ax.IDENT, self.repo),
                    "artifacts": [self.artifact(path) for path in (self.log, events, self.binary, info, inputs)]}
        self.receipt = {"schema_version": 2, "status": "failed", "platform": "darwin", "tested_sha": self.sha,
            "head_sha": self.sha, "repository": str(self.repo), "output_directory": str(self.evidence),
            "source_snapshot_sha256": snapshot["sha256"], "source_manifest": self.artifact(self.evidence / "source-manifest.json"),
            "map_sha256": digest((self.repo / "qa/feature-map.json").read_bytes()),
            "registry_sha256": digest((self.repo / "qa/regressions.json").read_bytes()),
            "native_build": {**common, "command": ["swift", "build", "--build-tests", "--jobs", "2"],
                             "artifacts": [self.artifact(self.evidence / "native-build/build.log")]},
            "native_discovery": {**common, "command": ax.native.discovery_command(self.evidence),
                "artifacts": [self.artifact(self.evidence / "native-discovery/test.log"),
                              self.artifact(self.evidence / "native-discovery/events.jsonl")]},
            "native_runs": [self.row]}
        self.save_receipt()
        self.context = ax.validate_original(self.evidence, self.repo)
        self.home = self.root / "home"
        self.reports = self.home / "Library/Logs/DiagnosticReports"
        self.reports.mkdir(parents=True)
        self.output = self.evidence.parent / "ax-crash-report"

    @staticmethod
    def iso(value):
        return datetime.fromtimestamp(value, timezone.utc).isoformat(timespec="milliseconds")

    def artifact(self, path):
        return {"path": str(path.relative_to(self.evidence)), "sha256": digest(path.read_bytes())}

    def save_receipt(self):
        (self.evidence / "result.json").write_text(json.dumps(self.receipt))

    def report(self):
        header = {"bug_type": "309", "bundleID": ax.host.INFO["CFBundleIdentifier"],
                  "timestamp": self.iso(self.started + 5)}
        body = {"pid": self.identity["pid"], "procPath": self.identity["executable"],
                "procName": "zeus-native-test-host", "procLaunch": self.iso(self.started - 0.1),
                "captureTime": self.iso(self.started + 5), "faultingThread": 0,
                "bundleInfo": {"CFBundleIdentifier": ax.host.INFO["CFBundleIdentifier"]},
                "exception": {"type": "EXC_BREAKPOINT", "signal": "SIGTRAP", "codes": "PRIVATE-CODES"},
                "threads": [{"triggered": True, "frames": [{"imageIndex": 0, "symbol": "_dispatch_assert_queue_fail"}],
                             "threadState": {"PRIVATE-REGISTER": "PRIVATE-VALUE"}},
                            {"frames": [{"imageIndex": 0, "symbol": "PRIVATE-OTHER-THREAD"}]}],
                "usedImages": [{"path": "/PRIVATE-PATH/libdispatch.dylib", "uuid": "PRIVATE-UUID"}],
                "asi": {"PRIVATE-PAYLOAD": "PRIVATE-ERROR"}, "environment": {"PRIVATE-KEY": "PRIVATE-SECRET"}}
        return header, body

    @staticmethod
    def raw(header, body):
        return (json.dumps(header) + "\n" + json.dumps(body)).encode()

    def write_report(self, name="zeus-native-test-host-fixture.ips", body=None, modified=None):
        header, original = self.report()
        path = self.reports / name
        path.write_bytes(self.raw(header, original if body is None else body))
        moment = self.started + 6 if modified is None else modified
        os.utime(path, (moment, moment))
        return path

    def run_main(self):
        validate, verify = ax.validate_original, ax.verify_unchanged
        with patch.object(ax, "require_hosted_mac"), patch.object(ax.Path, "home", return_value=self.home), \
             patch.object(ax, "validate_original", side_effect=lambda path: validate(path, self.repo)), \
             patch.object(ax, "verify_unchanged", side_effect=lambda context, path: verify(context, path, self.repo)):
            return ax.main(["--evidence", str(self.evidence), "--output", str(self.output)])

    def test_hosted_mac_and_restored_motion_environment_are_required(self):
        for system, github, environment in [("Linux", "true", "github-hosted"), ("Darwin", "false", "github-hosted"),
                                            ("Darwin", "true", "self-hosted")]:
            with self.subTest(system=system, environment=environment), patch.object(ax.platform, "system", return_value=system), \
                 patch.dict(os.environ, {"GITHUB_ACTIONS": github, "RUNNER_ENVIRONMENT": environment}), self.assertRaises(Invalid):
                ax.require_hosted_mac()
        with patch.object(ax.platform, "system", return_value="Darwin"), patch.dict(os.environ,
             {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted", ax.MARKER: "1"}), self.assertRaises(Invalid):
            ax.require_hosted_mac()

    def test_original_failure_selector_sha_and_compiler_barriers_are_required(self):
        original = copy.deepcopy(self.receipt)
        mutations = [lambda r: r.update(status="passed"), lambda r: r.update(tested_sha="0" * 40),
                     lambda r: r.update(native_runs=[]), lambda r: r["native_runs"].append(copy.deepcopy(r["native_runs"][0])),
                     lambda r: r["native_runs"][0].update(exit_code=0),
                     lambda r: r["native_runs"][0]["command"].__setitem__(4, "arbitrary selector"),
                     lambda r: r["native_build"].update(status="failed"),
                     lambda r: r["native_discovery"].update(status="failed")]
        for mutate in mutations:
            self.receipt = copy.deepcopy(original)
            mutate(self.receipt)
            self.save_receipt()
            with self.assertRaises(Invalid):
                ax.validate_original(self.evidence, self.repo)

    def test_changed_source_host_bundle_and_inputs_cannot_supply_evidence(self):
        for path in (self.source, self.binary, self.bundle, ax.host.inputs_path(self.evidence, ax.IDENT)):
            original = path.read_bytes()
            path.write_bytes(original + b"changed")
            with self.subTest(path=path.name), self.assertRaises(Invalid):
                ax.validate_original(self.evidence, self.repo)
            path.write_bytes(original)
        self.row["artifacts"] = self.row["artifacts"][:-1]
        self.save_receipt()
        with self.assertRaises(Invalid):
            ax.validate_original(self.evidence, self.repo)

    def test_telemetry_must_be_unique_and_match_exact_executable(self):
        for lines in ([], [self.identity, self.identity], [{**self.identity, "executable": "/foreign/host"}],
                      [{**self.identity, "pid": True}], [{**self.identity, "started": "2026-11-10T12:00:00"}]):
            self.log.write_text("".join(ax.IDENTITY_PREFIX + json.dumps(row) + "\n" for row in lines))
            self.row["artifacts"][0] = self.artifact(self.log)
            self.save_receipt()
            with self.assertRaises(Invalid):
                ax.validate_original(self.evidence, self.repo)

    def test_owned_crashed_thread_is_sanitized_and_bounded(self):
        header, body = self.report()
        body["threads"][0]["frames"] *= 30
        body["threads"][0]["frames"][0] = {"imageIndex": 0, "symbol": "/PRIVATE-PATH/secret.swift"}
        result = ax.parse_report(self.raw(header, body), self.context)
        self.assertEqual(len(result["frames"]), 24)
        self.assertTrue(result["frames_truncated"])
        self.assertEqual(result["frames"][0], {"image": "libdispatch.dylib", "symbol": "<unavailable-symbol>"})
        self.assertNotIn("PRIVATE", json.dumps(result))
        self.assertEqual(result["signal"], "SIGTRAP")

    def test_pid_path_launch_time_bundle_and_thread_identity_are_mandatory(self):
        header, original = self.report()
        for field, value in (("pid", 8), ("procPath", "/foreign/host")):
            self.assertIsNone(ax.parse_report(self.raw(header, {**original, field: value}), self.context))
        mutations = [lambda b: b.pop("procLaunch"), lambda b: b.update(procLaunch=self.iso(self.started - 100)),
                     lambda b: b.update(captureTime=self.iso(self.started + 100)), lambda b: b.update(pid=True),
                     lambda b: b.update(faultingThread=1), lambda b: b["threads"][1].update(triggered=True),
                     lambda b: b["bundleInfo"].update(CFBundleIdentifier="foreign"),
                     lambda b: b["exception"].update(signal="SIGABRT"),
                     lambda b: b["threads"][0]["frames"][0].update(imageIndex=999)]
        for mutate in mutations:
            body = copy.deepcopy(original)
            mutate(body)
            with self.assertRaises(Invalid):
                ax.parse_report(self.raw(header, body), self.context)

    def test_unknown_duplicate_nonfinite_and_trailing_report_formats_are_rejected(self):
        header, body = self.report()
        raw = self.raw(header, body)
        for invalid in (raw + b"{}", json.dumps(body).encode(), raw.replace(b'"pid": 4242', b'"pid": 4242, "pid": 4242'),
                        raw.replace(b'"pid": 4242', b'"pid": NaN'), raw.replace(b'"pid": 4242', b'"pid": 1e999'),
                        raw.replace(b'"309"', b'"308"')):
            with self.assertRaises((Invalid, ValueError)):
                ax.parse_report(invalid, self.context)

    def test_apple_ips_times_and_iso_host_telemetry_match_with_explicit_timezones(self):
        self.assertEqual(ax.timestamp("2026-11-10 13:59:48.6890 +0000"),
                         ax.timestamp("2026-11-10T13:59:48.689Z"))
        self.assertEqual(ax.timestamp("2026-11-10 14:59:48 +0100"),
                         ax.timestamp("2026-11-10T13:59:48+00:00"))
        header, body = self.report()
        for key in ("procLaunch", "captureTime"):
            body[key] = datetime.fromisoformat(body[key]).strftime("%Y-%m-%d %H:%M:%S.%f %z")
        header["timestamp"] = datetime.fromisoformat(header["timestamp"]).strftime("%Y-%m-%d %H:%M:%S %z")
        self.assertEqual(ax.parse_report(self.raw(header, body), self.context)["signal"], "SIGTRAP")
        for value in ("2026-11-10 13:59:48.6890", "2026-11-10T13:59:48", "yesterday", "2026-11-10 13:59:48 UTC"):
            with self.assertRaises(Invalid):
                ax.timestamp(value)

    def test_only_fresh_owned_names_are_opened_and_duplicates_are_ambiguous(self):
        self.write_report("OtherApp-private.ips").write_bytes(b"private unrelated contents")
        self.write_report("zeus-native-test-host-stale.ips", modified=self.started - 100).write_bytes(b"stale")
        # Writing updates mtime; restore the deliberate old timestamp.
        stale = self.reports / "zeus-native-test-host-stale.ips"
        os.utime(stale, (self.started - 100, self.started - 100))
        self.write_report()
        with patch.object(ax, "read_report", wraps=ax.read_report) as read:
            self.assertEqual(ax.collect_reports(self.context, self.reports)["signal"], "SIGTRAP")
            self.assertEqual(read.call_count, 1)
        self.write_report("zeus-native-test-host-duplicate.ips")
        with self.assertRaisesRegex(Invalid, "ambiguous"):
            ax.collect_reports(self.context, self.reports)

    def test_symlinked_roots_candidates_and_oversized_reports_are_not_read(self):
        actual = self.write_report()
        alias = self.root / "reports-alias"
        alias.symlink_to(self.reports, target_is_directory=True)
        with self.assertRaises(Invalid):
            ax.collect_reports(self.context, alias)
        link = self.reports / "zeus-native-test-host-link.ips"
        link.symlink_to(actual)
        os.utime(link, (self.started + 6, self.started + 6), follow_symlinks=False)
        with self.assertRaises(Invalid):
            ax.collect_reports(self.context, self.reports)
        link.unlink()
        actual.write_bytes(b"x" * (ax.MAX_REPORT + 1))
        os.utime(actual, (self.started + 6, self.started + 6))
        with self.assertRaises(Invalid):
            ax.collect_reports(self.context, self.reports)

    def test_directory_candidate_and_cumulative_read_limits_are_finite(self):
        for index in range(5):
            self.write_report(f"zeus-native-test-host-{index}.ips")
        with self.assertRaisesRegex(Invalid, "candidate limit"):
            ax.collect_reports(self.context, self.reports)
        for path in self.reports.iterdir():
            path.unlink()
        header, body = self.report()
        body["pid"] += 1
        path = self.write_report(body=body)
        writes = 0
        def replace_candidate(_seconds):
            nonlocal writes, path
            path.unlink()
            writes += 1
            path = self.write_report(f"zeus-native-test-host-new-{writes}.ips", body=body)
        with patch.object(ax.time, "sleep", side_effect=replace_candidate), patch.object(ax, "read_report", wraps=ax.read_report) as read:
            with self.assertRaisesRegex(Invalid, "cumulative"):
                ax.collect_reports(self.context, self.reports)
            self.assertEqual(read.call_count, 4)
        path.unlink()
        for index in range(1025):
            (self.reports / f"unrelated-{index}").touch()
        with self.assertRaisesRegex(Invalid, "enumeration"):
            ax.collect_reports(self.context, self.reports)

    def test_report_open_rechecks_identity_and_known_build_symlink_is_allowed(self):
        path = self.write_report()
        before = path.stat()
        signature = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
        path.write_bytes(b"changed report")
        directory = os.open(self.reports, os.O_RDONLY | os.O_DIRECTORY)
        try:
            with self.assertRaises(Invalid):
                ax.read_report(path.name, signature, directory)
        finally:
            os.close(directory)
        debug = self.repo / ".build/debug"
        moved = self.repo / ".build/architecture-debug"
        debug.rename(moved)
        debug.symlink_to(moved.name, target_is_directory=True)
        inputs = ax.host.inputs_path(self.evidence, ax.IDENT)
        inputs.write_text(json.dumps(ax.host.input_provenance(self.repo, {"platform": "/selected/Xcode.platform"})))
        self.row["artifacts"][-1] = self.artifact(inputs)
        self.save_receipt()
        context = ax.validate_original(self.evidence, self.repo)
        ax.verify_unchanged(context, self.evidence, self.repo)
        duplicate = self.root / "duplicate-bundle"
        duplicate.write_bytes(self.bundle.read_bytes())
        self.bundle.unlink()
        self.bundle.symlink_to(duplicate)
        with self.assertRaises(Invalid):
            ax.verify_unchanged(context, self.evidence, self.repo)

    def test_main_persists_only_sanitized_diagnostic_and_preserves_failed_receipt(self):
        self.write_report()
        original = (self.evidence / "result.json").read_bytes()
        self.assertEqual(self.run_main(), 0)
        result = json.loads((self.output / "result.json").read_text())
        self.assertEqual(result["status"], "collected")
        self.assertTrue(result["diagnostic_only"])
        self.assertFalse(result["acceptance_credit"])
        self.assertTrue(result["original_evidence_unchanged"])
        self.assertNotIn("PRIVATE", json.dumps(result))
        self.assertEqual([path.name for path in self.output.iterdir()], ["result.json"])
        self.assertEqual((self.evidence / "result.json").read_bytes(), original)

    def test_existing_output_and_original_failure_are_never_overwritten(self):
        self.output.mkdir()
        protected = self.output / "result.json"
        protected.write_bytes(b"existing diagnostic must remain")
        self.assertEqual(self.run_main(), 1)
        self.assertEqual(protected.read_bytes(), b"existing diagnostic must remain")
        self.assertEqual(json.loads((self.evidence / "result.json").read_text())["status"], "failed")

    def test_missing_report_or_interruption_stays_unavailable(self):
        with patch.object(ax, "POLL_SECONDS", 0):
            self.assertEqual(self.run_main(), 1)
        result = json.loads((self.output / "result.json").read_text())
        self.assertEqual(result["status"], "unavailable")
        (self.output / "result.json").unlink()
        self.output.rmdir()
        with patch.object(ax, "collect_reports", side_effect=KeyboardInterrupt):
            self.assertEqual(self.run_main(), 1)
        self.assertEqual(json.loads((self.output / "result.json").read_text())["reason"], "interrupted")

    def test_changed_original_after_collection_cannot_emit_crash_evidence(self):
        def tamper(_context, _reports):
            self.log.write_text("changed original evidence")
            return {"signal": "SIGTRAP"}
        with patch.object(ax, "collect_reports", side_effect=tamper):
            self.assertEqual(self.run_main(), 1)
        result = json.loads((self.output / "result.json").read_text())
        self.assertEqual(result["status"], "unavailable")
        self.assertFalse(result["original_evidence_unchanged"])
        self.assertNotIn("crash", result)

    def test_refusal_reports_fixed_phase_without_raw_parser_payload(self):
        for phase in ("report-time", "report-frames"):
            header, body = self.report()
            if phase == "report-time":
                body["procLaunch"] = "PRIVATE-INVALID-TIMESTAMP"
            else:
                body["threads"][0]["frames"] = "PRIVATE-INVALID-FRAMES"
            path = self.write_report(body=body)
            console = io.StringIO()
            with redirect_stdout(console):
                self.assertEqual(self.run_main(), 1)
            result = json.loads((self.output / "result.json").read_text())
            self.assertEqual(result["phase"], phase)
            self.assertIn("phase=" + phase, console.getvalue())
            self.assertNotIn("PRIVATE", console.getvalue() + json.dumps(result))
            (self.output / "result.json").unlink()
            self.output.rmdir()
            path.unlink()
        self.row["exit_code"] = 0
        self.save_receipt()
        console = io.StringIO()
        with redirect_stdout(console):
            self.assertEqual(self.run_main(), 1)
        self.assertIn("phase=provenance", console.getvalue())
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
