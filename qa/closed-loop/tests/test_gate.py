import copy
import importlib.util
import json
import re
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("zeus_required_gate", Path(__file__).resolve().parents[1] / "gate.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class RequiredGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="zeus-gate-")
        self.addCleanup(self.temporary.cleanup)
        self.inputs = Path(self.temporary.name)
        self.sha = "a" * 40
        self.head = "b" * 40
        # Freeze only the source-snapshot provider for unit isolation while other agents edit.
        # The gate still compares every manifest/hash and regenerates real portable packages.
        policy = gate.policy_modules()
        self.source_snapshot = policy[1].source_snapshot(policy[0], self.inputs)
        provider = patch.object(gate, "policy_modules", return_value=policy)
        provider.start()
        self.addCleanup(provider.stop)
        source_provider = patch.object(policy[1], "source_snapshot", return_value=self.source_snapshot)
        source_provider.start()
        self.addCleanup(source_provider.stop)
        self.needs = {job: {"result": "success"} for job in gate.REQUIRED}
        for job, checks in gate.REQUIRED.items():
            root = self.inputs / f"zeus-check-{job}"
            root.mkdir()
            if job == "feature-map":
                self.write(root / "result.json", self.make_feature_result(root))
                files = ["result.json"]
            else:
                for check in checks:
                    (root / f"{check}.log").write_text("command passed\n")
                lines = {"app": "Test run with 2 tests in 1 suite passed", "extension": "# tests 3\n# pass 3\n# fail 0\n# cancelled 0\n# skipped 0\n# todo 0",
                         "release-scripts": "Ran 13 tests in 1.0s\nOK"}
                if job == "app":
                    _, contracts, _, _, definitions, _ = gate.load_policy()
                    names = sorted({name for row in definitions.values() if row["kind"] == "native-fixture"
                                    for name in contracts.runnable_functions((policy[0] / row["file"]).read_text())})
                    lines[job] = "".join(f"✔ Test {name}() passed after 0.001 seconds.\n" for name in names)
                    lines[job] += f"✔ Test run with {len(names)} tests in 1 suite passed after 0.1 seconds."
                (root / "test.log").write_text(lines[job] + "\n")
                files = [f"{check}.log" for check in checks]
            self.write(root / "job.json", {
                "schema_version": 1, "job": job, "tested_sha": self.sha, "expected_sha": self.sha,
                "head_sha": self.head, "run_id": "42", "run_attempt": "1",
                "checks": {check: "success" for check in checks},
                "files": {name: {"sha256": gate.digest(root / name), "bytes": (root / name).stat().st_size} for name in files},
            })

    def make_feature_result(self, root):
        repo, contracts, portable, feature_map, definitions, registry = gate.load_policy()
        functions = {ident: set() for ident in ["closed-loop-selftests", *definitions]}
        functions["closed-loop-selftests"].add("test_synthetic_contract")
        for feature in feature_map["features"]:
            for obligation in feature["obligations"]:
                functions[obligation["check"]].update(case["function"] for case in obligation["cases"])
        for entry in registry:
            functions[entry["check"]].add(entry["guard"]["function"])
        checks = []
        for ident, definition in [("closed-loop-selftests", {"kind": "selftests"}), *definitions.items()]:
            kind = definition["kind"]
            row = {"id": ident, "kind": kind, "status": "not-run", "command": [], "exit_code": None,
                   "tests": 0, "suites": 0, "passed_functions": [], "artifacts": []}
            if kind == "unimplemented":
                row.update(status="unimplemented", reason=definition["reason"])
            elif kind != "native-fixture":
                folder = root / ident
                folder.mkdir()
                names = sorted(functions[ident])
                row.update(status="passed", command=["swift", "test"], exit_code=0, tests=len(names),
                           suites=1, passed_functions=names)
                if kind == "portable":
                    package = portable.prepare(folder, definition["group"])
                    row["package"] = str(package.relative_to(root))
                    row["artifacts"].append({"path": str((package / "validation-manifest.json").relative_to(root)),
                                             "sha256": gate.digest(package / "validation-manifest.json")})
                    log = "".join(f"✔ Test {name}() passed after 0.001 seconds.\n" for name in names)
                    log += f"✔ Test run with {len(names)} tests in 1 suite passed after 0.1 seconds.\n"
                else:
                    log = "".join(f"{name} (Fixture) ... ok\n" for name in names)
                    log += f"Ran {len(names)} tests in 0.1s\nOK\n"
                (folder / "test.log").write_text(log)
                row["artifacts"].append({"path": str((folder / "test.log").relative_to(root)),
                                         "sha256": gate.digest(folder / "test.log")})
            checks.append(row)
        by_id = {check["id"]: check for check in checks}
        source_manifest = contracts.source_snapshot(repo, root)
        self.write(root / "source-manifest.json", source_manifest)
        return {"schema_version": 1, "status": "passed", "mode": "development", "tested_sha": self.sha,
                "head_sha": self.head, "source_snapshot_sha256": source_manifest["sha256"], "release_ready": False,
                "platform": "linux" if sys.platform.startswith("linux") else "darwin",
                "source_manifest": {"path": "source-manifest.json", "sha256": gate.digest(root / "source-manifest.json")},
                "map_sha256": gate.digest(repo / "qa/feature-map.json"), "registry_sha256": gate.digest(repo / "qa/regressions.json"),
                "checks": checks, "features": contracts.evaluate_features(feature_map, by_id, root),
                "totals": {"tests": sum(check["tests"] for check in checks)}}

    def write(self, path, value):
        path.write_text(json.dumps(value))

    def root(self, job):
        return self.inputs / f"zeus-check-{job}"

    def update_receipt(self, job, change):
        path = self.root(job) / "job.json"
        value = json.loads(path.read_text())
        change(value)
        self.write(path, value)

    def refresh_file(self, job, name):
        path = self.root(job) / name
        self.update_receipt(job, lambda receipt: receipt["files"].update({name: {"sha256": gate.digest(path), "bytes": path.stat().st_size}}))

    def update_map(self, change):
        path = self.root("feature-map") / "result.json"
        value = json.loads(path.read_text())
        change(value)
        self.write(path, value)
        self.refresh_file("feature-map", "result.json")

    def evaluate(self, mode="development"):
        return gate.evaluate(self.needs, self.inputs, self.sha, self.head, "42", "1", mode)

    def assert_blocked(self):
        result = self.evaluate()
        self.assertEqual(result["status"], "failed", result)
        self.assertTrue(result["errors"])

    def test_complete_current_revision_evidence_passes(self):
        result = self.evaluate()
        self.assertEqual(result["status"], "passed", result)
        self.assertGreater(result["jobs"]["feature-map"]["tests"], 0)

    def use_ancestor_alias(self):
        alias_directory = tempfile.TemporaryDirectory(prefix="zeus-gate-ancestor-")
        self.addCleanup(alias_directory.cleanup)
        alias = Path(alias_directory.name) / "var"
        alias.symlink_to(self.inputs.parent.resolve(), target_is_directory=True)
        self.inputs = alias / self.inputs.name
        self.assertNotEqual(self.inputs.absolute(), self.inputs.resolve())

    def test_trusted_output_ancestor_alias_accepts_valid_packages(self):
        # Models macOS /var -> /private/var without editing the host filesystem.
        self.use_ancestor_alias()
        result = self.evaluate()
        self.assertEqual(result["status"], "passed", result)

    def test_ancestor_alias_does_not_allow_child_package_symlinks_or_escape(self):
        self.use_ancestor_alias()
        result = json.loads((self.root("feature-map") / "result.json").read_text())
        package = next(row["package"] for row in result["checks"] if row["kind"] == "portable")
        source = self.root("feature-map") / package / "Package.swift"
        outside = self.inputs.parent / (self.inputs.name + "-redirected.swift")
        outside.write_bytes(source.read_bytes())
        self.addCleanup(outside.unlink)
        source.unlink()
        source.symlink_to(outside)
        blocked = self.evaluate()
        self.assertEqual(blocked["status"], "failed", blocked)
        self.assertTrue(any("source package is redirected" in error for error in blocked["errors"]), blocked)
        source.unlink()
        source.write_bytes(outside.read_bytes())
        self.update_map(lambda value: next(row for row in value["checks"] if row["kind"] == "portable").update(package="../outside"))
        self.assert_blocked()

    def test_any_non_success_prerequisite_blocks(self):
        for job in gate.REQUIRED:
            for result in ("failure", "cancelled", "skipped", "timed_out", "neutral", "", "SUCCESS", "true", True, False, None, {"result": "success"}):
                with self.subTest(job=job, result=result):
                    self.needs[job]["result"] = result
                    self.assert_blocked()
            self.needs[job]["result"] = "success"

    def test_missing_unexpected_and_non_object_job_sets_block(self):
        original = copy.deepcopy(self.needs)
        for job in gate.REQUIRED:
            self.needs = copy.deepcopy(original)
            del self.needs[job]
            self.assert_blocked()
        self.needs = dict(original, optional={"result": "success"})
        self.assert_blocked()
        for bad in (None, [], "success", True):
            self.needs = bad
            self.assert_blocked()

    def test_success_job_cannot_hide_skipped_or_missing_commands(self):
        self.update_receipt("app", lambda r: r["checks"].update(test="skipped"))
        self.assert_blocked()
        self.update_receipt("app", lambda r: r["checks"].pop("test"))
        self.assert_blocked()

    def test_missing_artifact_blocks_even_when_jobs_succeed(self):
        (self.root("app") / "test.log").unlink()
        self.assert_blocked()

    def test_missing_or_malformed_receipt_blocks(self):
        (self.root("extension") / "job.json").write_text("not JSON")
        self.assert_blocked()
        (self.root("extension") / "job.json").unlink()
        self.assert_blocked()

    def test_wrong_revision_head_or_run_cannot_be_reused(self):
        path = self.root("app") / "job.json"
        original = path.read_text()
        for field, value in (("tested_sha", "d" * 40), ("head_sha", "d" * 40), ("expected_sha", "d" * 40),
                             ("run_id", "41"), ("run_attempt", "2"), ("job", "another")):
            with self.subTest(field=field):
                path.write_text(original)
                self.update_receipt("app", lambda r: r.update({field: value}))
                self.assert_blocked()

    def test_tampered_test_log_blocks(self):
        (self.root("release-scripts") / "test.log").write_text("Ran 100 tests in 1s\nOK\n")
        self.assert_blocked()

    def test_zero_tests_is_not_green(self):
        for job, line in (("app", "Test run with 0 tests passed\n"), ("extension", "# tests 0\n"),
                          ("release-scripts", "Ran 0 tests in 1.0s\nOK\n")):
            with self.subTest(job=job):
                (self.root(job) / "test.log").write_text(line)
                self.refresh_file(job, "test.log")
                self.assert_blocked()

    def test_real_swift_testing_and_node_summary_formats(self):
        path = self.root("app") / "test.log"
        path.write_text("Executed 0 tests, with 0 failures\n✔ Test run with 20 tests in 2 suites passed after 0.1 seconds.\n")
        self.assertEqual(gate.positive_test_count("app", path), 20)
        path.write_text("ℹ tests 12\nℹ pass 12\nℹ fail 0\nℹ cancelled 0\nℹ skipped 0\nℹ todo 0\n")
        self.assertEqual(gate.positive_test_count("extension", path), 12)

    def test_failed_or_skipped_test_summaries_do_not_pass(self):
        cases = (("app", "Executed 4 tests, with 0 failures\nTest run with 2 tests in 1 suite failed\n"),
                 ("extension", "# tests 3\n# pass 2\n# fail 0\n# cancelled 0\n# skipped 1\n# todo 0\n"),
                 ("release-scripts", "Ran 3 tests in 1.0s\nFAILED (failures=1)\n"))
        for job, text in cases:
            with self.subTest(job=job):
                (self.root(job) / "test.log").write_text(text)
                self.refresh_file(job, "test.log")
                self.assert_blocked()

    def test_duplicate_json_keys_and_nonfinite_numbers_are_rejected(self):
        for text in ('{"status":"failed","status":"passed"}', '{"tests":NaN}', '{"tests":Infinity}'):
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    gate.load_json(text)

    def test_feature_map_false_green_values_and_totals_block(self):
        original = (self.root("feature-map") / "result.json").read_text()
        changes = [lambda r: r.update(status="skipped"), lambda r: r.update(schema_version=True),
                   lambda r: r.update(release_ready="true"), lambda r: r["checks"][0].update(exit_code=False),
                   lambda r: r["checks"][0].update(tests=True), lambda r: r["checks"][0].update(status="skipped"),
                   lambda r: r.update(checks=[]), lambda r: r.update(features=[]),
                   lambda r: r["totals"].update(tests=999), lambda r: r.update(tested_sha="d" * 40),
                   lambda r: r["checks"].append(copy.deepcopy(r["checks"][0]))]
        for change in changes:
            with self.subTest(change=change):
                (self.root("feature-map") / "result.json").write_text(original)
                self.update_map(change)
                self.assert_blocked()

    def test_feature_map_evidence_must_exist_and_match(self):
        (self.root("feature-map") / "closed-loop-selftests/test.log").write_text("changed")
        self.assert_blocked()

    def test_missing_native_guard_blocks_despite_other_passing_tests(self):
        _, _, _, feature_map, definitions, _ = gate.load_policy()
        case = next(case for feature in feature_map["features"] for obligation in feature["obligations"]
                    if definitions[obligation["check"]]["kind"] == "native-fixture" for case in obligation["cases"])
        log = self.root("app") / "test.log"
        log.write_text("\n".join(line for line in log.read_text().splitlines() if f"Test {case['function']}()" not in line))
        self.refresh_file("app", "test.log")
        result = self.evaluate()
        self.assertEqual(result["status"], "failed", result)
        self.assertTrue(any(case["function"] in error for error in result["errors"]), result)

    def test_missing_or_changed_feature_obligation_blocks(self):
        original = (self.root("feature-map") / "result.json").read_text()
        for change in (lambda r: r.update(features=[f for f in r["features"] if f["id"] != "F13"]),
                       lambda r: r["features"][0]["obligations"][0].update(status="failed")):
            (self.root("feature-map") / "result.json").write_text(original)
            self.update_map(change)
            self.assert_blocked()

    def test_source_manifest_must_match_current_bytes(self):
        self.update_map(lambda r: r.update(source_snapshot_sha256="d" * 64))
        self.assert_blocked()

    def test_development_receipt_cannot_smuggle_a_native_compiler_barrier(self):
        self.update_map(lambda r: r.update(native_build={"status": "passed"}))
        result = self.evaluate()
        self.assertEqual(result["status"], "failed", result)
        self.assertTrue(any("only valid for full macOS" in error for error in result["errors"]), result)

    def test_full_run_requires_full_mode_and_completed_obligations(self):
        self.assertEqual(self.evaluate("full")["status"], "failed")
        self.update_map(lambda r: r.update(mode="full"))
        self.assertEqual(self.evaluate("full")["status"], "failed")
        self.update_map(lambda r: r.update(release_ready=True))
        self.assertEqual(self.evaluate("full")["status"], "failed")  # Unimplemented obligations cannot be overridden.

    def test_artifacts_cannot_escape_or_follow_symlinks(self):
        path = self.root("feature-map") / "closed-loop-selftests/test.log"
        outside = self.inputs / "outside.log"
        outside.write_text(path.read_text())
        path.unlink()
        path.symlink_to(outside)
        self.assert_blocked()
        path.unlink()
        self.update_map(lambda r: r["checks"][0]["artifacts"][0].update(path="../outside.log"))
        self.assert_blocked()


class NativeBuildGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="zeus-native-build-gate-")
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)
        self.contracts = gate.policy_modules()[1]
        folder = self.output / "native-build"
        folder.mkdir()
        self.log = folder / "build.log"
        self.log.write_text("Building for debugging...\nBuild complete! (0.1s)\n")
        self.result = {"platform": "darwin", "source_snapshot_sha256": "a" * 64,
                       "native_build": {"status": "passed", "command": ["swift", "build", "--build-tests", "--jobs", "2"],
                                        "exit_code": 0, "source_snapshot_sha256": "a" * 64, "duration_seconds": 0.1,
                                        "artifacts": [{"path": "native-build/build.log", "sha256": gate.digest(self.log)}]}}
        self.definition = {"suite": "SelectedTests", "file": "Tests/ZeusAppTests/SelectedTests.swift"}
        self.command = ["swift", "test", "--skip-build", "--jobs", "2", "--filter", r"^ZeusAppTests\.SelectedTests/"]

    def validate(self, mode="full"):
        return gate.validate_native_compilation(self.result, self.output, mode, self.contracts)

    def test_verified_native_build_allows_only_its_exact_fixture_command(self):
        jobs = self.validate()
        self.assertEqual(jobs, "2")
        gate.validate_native_command(self.command, self.definition, jobs)
        core = {"suite": "SelectedTests", "file": "Tests/ZeusCoreTests/SelectedTests.swift"}
        gate.validate_native_command([*self.command[:-1], r"^ZeusCoreTests\.SelectedTests/"], core, jobs)

    def test_missing_failed_or_stale_compilation_cannot_authorize_native_reuse(self):
        original = copy.deepcopy(self.result)
        changes = [lambda r: r.pop("native_build"), lambda r: r.update(native_build=None),
                   lambda r: r["native_build"].update(status="failed"),
                   lambda r: r["native_build"].update(exit_code=1),
                   lambda r: r["native_build"].update(exit_code=False),
                   lambda r: r["native_build"].update(source_snapshot_sha256="b" * 64),
                   lambda r: r["native_build"].update(command=["swift", "build"]),
                   lambda r: r["native_build"]["command"].append("--skip-build")]
        for change in changes:
            with self.subTest(change=change):
                self.result = copy.deepcopy(original)
                change(self.result)
                with self.assertRaises(ValueError):
                    self.validate()

    def test_missing_or_forged_compiler_log_cannot_authorize_native_reuse(self):
        for text in ("Build complete! (0.1s)\nerror: native compile failed\n", "Building for debugging...\n",
                     "Build complete! (0.1s)\nCHECK TIMEOUT after 10 seconds\n"):
            with self.subTest(text=text):
                self.log.write_text(text)
                self.result["native_build"]["artifacts"][0]["sha256"] = gate.digest(self.log)
                with self.assertRaises(ValueError):
                    self.validate()
        self.log.unlink()
        with self.assertRaises(ValueError):
            self.validate()

    def test_compiler_log_hash_and_containment_are_required(self):
        self.log.write_text("Build complete! (changed bytes)\n")
        with self.assertRaises(ValueError):
            self.validate()
        self.result["native_build"]["artifacts"][0]["sha256"] = gate.digest(self.log)
        outside = self.output / "outside.log"
        outside.write_bytes(self.log.read_bytes())
        self.log.unlink()
        self.log.symlink_to(outside)
        with self.assertRaises(ValueError):
            self.validate()

    def test_barrier_is_for_full_macos_only(self):
        for mode, platform in (("development", "darwin"), ("development", "linux"), ("full", "linux")):
            with self.subTest(mode=mode, platform=platform):
                self.result["platform"] = platform
                with self.assertRaises(ValueError):
                    self.validate(mode)
        self.result.pop("native_build")
        self.assertIsNone(self.validate("full"))
        with self.assertRaises(ValueError):
            gate.validate_native_command(self.command, self.definition, None)

    def test_native_reuse_rejects_changed_jobs_flags_module_or_suite(self):
        jobs = self.validate()
        mutations = [lambda c: c.remove("--skip-build"), lambda c: c.__setitem__(4, "3"),
                     lambda c: c.__setitem__(-1, "SelectedTests"),
                     lambda c: c.__setitem__(-1, r"^ZeusCoreTests\.SelectedTests/"),
                     lambda c: c.__setitem__(-1, r"^ZeusAppTests\.UnreviewedTests/"),
                     lambda c: c.append("--parallel")]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                command = self.command.copy()
                mutate(command)
                with self.assertRaises(ValueError):
                    gate.validate_native_command(command, self.definition, jobs)


class WorkflowContractTests(unittest.TestCase):
    def test_workflow_covers_all_pushes_and_preserves_required_failures(self):
        workflow = (Path(__file__).resolve().parents[3] / ".github/workflows/build.yml").read_text()
        events = workflow.split("on:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertIn("  push:\n  pull_request:\n", events)
        for event in ("merge_group:", "schedule:", "workflow_dispatch:"):
            self.assertIn(event, events)
        for unsafe in ("pull_request_target", "continue-on-error:", "paths-ignore:", "branches-ignore:"):
            self.assertNotIn(unsafe, workflow)
        aggregate = workflow.split("  required-checks:\n", 1)[1]
        self.assertIn("    if: always()", aggregate)
        needs = re.search(r"^    needs: \[(.+)\]$", aggregate, re.MULTILINE)
        self.assertIsNotNone(needs)
        self.assertEqual({value.strip() for value in needs[1].split(",")}, set(gate.REQUIRED))
        self.assertIn("ZEUS_NEEDS_JSON: ${{ toJSON(needs) }}", aggregate)
        self.assertIn("gate.py evaluate", aggregate)
        self.assertIn("cancel-in-progress: false", workflow)
        self.assertIn("${{ github.event_name }}-${{ github.ref }}-${{ github.sha }}", workflow)
        self.assertEqual(workflow.count("ref: ${{ github.sha }}"), len(gate.REQUIRED) + 1)
        self.assertIn("github.ref == 'refs/heads/main'", workflow)
        self.assertIn("github.event_name == 'schedule'", workflow)
        self.assertIn('native_filter="$(python3 qa/closed-loop/gate.py native-filter)"', workflow)
        self.assertIn('scripts/test.sh --filter "$native_filter"', workflow)
        self.assertGreaterEqual(workflow.count("if-no-files-found: error"), len(gate.REQUIRED) + 1)

    def test_native_filter_is_anchored_to_only_reviewed_map_suites(self):
        _, _, _, _, definitions, _ = gate.load_policy()
        pattern = gate.native_filter()
        rows = [row for row in definitions.values() if row["kind"] == "native-fixture"]
        self.assertEqual(len(pattern.split("|")), len(rows))
        for row in rows:
            module = "ZeusAppTests" if row["file"].startswith("Tests/ZeusAppTests/") else "ZeusCoreTests"
            self.assertRegex(module + "." + row["suite"] + "/fixture", pattern)
        for unsafe in ("ZeusAppTests.UnreviewedCameraTests/fixture", "ZeusAppTests.PrefixPermissionsCaptureTests/fixture",
                       "OtherModule.PermissionsCaptureTests/fixture", "ZeusAppTests.PermissionsCaptureTestsExtra/fixture"):
            self.assertNotRegex(unsafe, pattern)


if __name__ == "__main__":
    unittest.main(verbosity=2)
