"""Process partition and exact-union rejection fixtures, not native UI acceptance."""
import copy
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import native as driver
import native_evidence as evidence
from contracts import Invalid, digest, source_snapshot
import test_native_evidence as fixtures


class NativeProcessRunnerTests(unittest.TestCase):
    def definitions(self):
        apps = [{"id": "native-" + name, "kind": "native-fixture", "tier": "native-integration",
                 "scope": "Synthetic process-control fixture.", "suite": name,
                 "file": "Tests/ZeusAppTests/" + name + ".swift"}
                for name in ("SnapshotTests", "LicenseTests", "AccessibilityTests")]
        core = {"id": "native-ZeusCoreTests", "kind": "native-module", "module": "ZeusCoreTests",
                "tier": "native-integration", "scope": "Synthetic Core partition."}
        return [apps[0], core, *apps[1:]]

    def test_every_native_selector_gets_its_own_sequential_process_core_first(self):
        definitions = self.definitions()
        result = {"native_build": {"status": "passed"}, "native_discovery": {"status": "passed"}}
        calls = []
        active = False
        def run(definition, args, output, build, discovery, all_definitions):
            nonlocal active
            self.assertFalse(active)
            active = True
            self.assertIs(all_definitions, definitions)
            calls.append(evidence.run_command([definition], args.jobs, output, definition["id"]))
            active = False
            return {"id": definition["id"], "kind": definition["kind"], "status": "passed", "tests": 1}
        with patch.object(driver.runner, "run_native_check", side_effect=run):
            driver.run_partitions(SimpleNamespace(jobs=2), Path("/owned-evidence"), result, definitions)
        self.assertEqual([row["id"] for row in result["native_runs"]],
                         ["native-ZeusCoreTests", "native-SnapshotTests", "native-LicenseTests", "native-AccessibilityTests"])
        filters = [command[command.index("--filter") + 1] for command in calls]
        self.assertEqual(filters, [r"^ZeusCoreTests(?:\.|/)", r"^ZeusAppTests\.SnapshotTests/",
                                   r"^ZeusAppTests\.LicenseTests/", r"^ZeusAppTests\.AccessibilityTests/"])
        self.assertEqual(len({command[command.index("--event-stream-output-path") + 1] for command in calls}), 4)

    def test_failed_or_exceptional_partition_cannot_prevent_later_required_suites(self):
        for exceptional in (False, True):
            with self.subTest(exceptional=exceptional):
                definitions = self.definitions()
                result = {"native_build": {}, "native_discovery": {}}
                calls = []
                def run(definition, *args):
                    calls.append(definition["id"])
                    if definition["id"] == "native-SnapshotTests":
                        if exceptional:
                            raise Invalid("synthetic invalid artifact")
                        return {"id": definition["id"], "kind": definition["kind"], "status": "failed", "reason": "missing runEnded"}
                    return {"id": definition["id"], "kind": definition["kind"], "status": "passed"}
                with patch.object(driver.runner, "run_native_check", side_effect=run):
                    driver.run_partitions(SimpleNamespace(jobs=2), Path("/owned-evidence"), result, definitions)
                self.assertEqual(len(calls), 4)
                self.assertEqual([row["status"] for row in result["native_runs"]], ["passed", "failed", "passed", "passed"])

    def test_partitions_reject_duplicate_or_broadened_selections(self):
        definitions = self.definitions()
        for invalid in (definitions[0:1], definitions + [definitions[0]],
                        definitions + [{**definitions[0], "id": "another-id"}],
                        [{**definitions[1], "module": "ZeusAppTests"}, *definitions[2:]]):
            with self.assertRaises(Invalid):
                evidence.partitions(invalid)


class NativePartitionReceiptTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.NativeEventEvidenceTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root, self.result = self.fixture.receipt()
        self.repo = self.fixture.repo
        self.core = {"id": "native-ZeusCoreTests", "kind": "native-module", "module": "ZeusCoreTests"}
        self.app = {"id": "native-AlphaTests", "kind": "native-fixture", "suite": "AlphaTests",
                    "file": "Tests/ZeusAppTests/AlphaTests.swift"}
        self.definitions = [self.app, self.core]  # Map order must not put Core second in execution.
        source = self.repo / self.app["file"]
        source.parent.mkdir()
        source.write_text("import Testing\nstruct AlphaTests {\n    @Test func appExample() {}\n}\n")
        suite = "ZeusAppTests.AlphaTests"
        ident = suite + "/appExample()/AlphaTests.swift:3:6"
        payload = {"kind": "function", "id": ident, "name": "appExample()", "isParameterized": False,
                   "sourceLocation": {"_filePath": str(source), "fileID": "ZeusAppTests/AlphaTests.swift", "line": 3, "column": 6}}
        declarations = [{"kind": "test", "version": 0, "payload": {"kind": "suite", "id": suite}},
                        {"kind": "test", "version": 0, "payload": payload}]
        event = self.fixture.event
        rows = declarations + [event("runStarted"), event("testStarted", suite), event("testStarted", ident),
                               event("testEnded", ident, "pass"), event("testEnded", suite, "pass"), event("runEnded", symbol="pass")]
        folder = self.root / self.app["id"]
        folder.mkdir()
        (folder / "test.log").write_text("✔ Test appExample() passed after 0.1 seconds.\n✔ Test run with 1 test in 1 suite passed after 0.1 seconds.\n")
        (folder / "events.jsonl").write_text("".join(json.dumps(row) + "\n" for row in rows))
        discovery = self.root / "native-discovery/events.jsonl"
        discovery.write_text(discovery.read_text() + "".join(json.dumps(row) + "\n" for row in declarations))
        self.compiled = evidence.discovery(discovery, self.definitions, self.repo)
        app_metrics = evidence.execution(folder / "events.jsonl", self.compiled, [self.app], self.repo)
        row = {"id": self.app["id"], "kind": "native-fixture", "tier": "native-integration", "scope": "Synthetic partition fixture.",
               "status": "passed", "exit_code": 0, "command": evidence.run_command([self.app], 2, self.root, self.app["id"]),
               **app_metrics, "passed_functions": ["appExample"], "artifacts": [self.artifact(folder / name) for name in ("test.log", "events.jsonl")]}
        self.result["native_runs"].append(row)
        core_cases = self.result["native_runs"][0]["passed_cases"]
        self.result["native_summary"] = {"tests": 2, "suites": 2, "parameter_cases": 0,
                                         "passed_cases": sorted(core_cases + app_metrics["passed_cases"], key=lambda item: item["id"])}
        self.result["native_discovery"]["artifacts"] = [self.artifact(self.root / "native-discovery" / name) for name in ("test.log", "events.jsonl")]
        manifest = source_snapshot(self.repo, self.root)
        (self.root / "source-manifest.json").write_text(json.dumps(manifest))
        self.result["source_manifest"] = self.artifact(self.root / "source-manifest.json")
        for obj in (self.result, self.result["native_build"], self.result["native_discovery"]):
            obj["source_snapshot_sha256"] = manifest["sha256"]

    def artifact(self, path):
        return {"path": str(path.relative_to(self.root)), "sha256": digest(path.read_bytes())}

    def validate(self, result=None):
        (self.root / "result.json").write_text(json.dumps(result or self.result))
        return evidence.validate_receipt(self.root, "a" * 40, "b" * 40, self.definitions, self.repo)

    def test_complete_disjoint_partition_union_recomputes_every_process(self):
        metrics = self.validate()
        self.assertEqual(metrics["tests"], 2)
        self.assertEqual({row["file"] for row in metrics["passed_cases"]},
                         {"Tests/ZeusCoreTests/SampleTests.swift", self.app["file"]})

    def test_missing_duplicate_reordered_or_failed_partition_cannot_use_aggregate_success(self):
        original = self.result["native_runs"]
        for rows in (original[:1], original * 2, list(reversed(original)),
                     [original[0], {**original[1], "status": "failed"}]):
            with self.assertRaises(Invalid):
                self.validate({**self.result, "native_runs": rows})

    def test_broadened_selector_or_forged_summary_cannot_borrow_other_partition_proof(self):
        changed = copy.deepcopy(self.result)
        changed["native_runs"][1]["command"] = evidence.run_command(self.definitions, 2, self.root, self.app["id"])
        with self.assertRaises(Invalid):
            self.validate(changed)
        changed = copy.deepcopy(self.result)
        changed["native_summary"]["tests"] = 99
        with self.assertRaises(Invalid):
            self.validate(changed)

    def test_exit_zero_with_incomplete_partition_events_fails_despite_other_success(self):
        path = self.root / self.app["id"] / "events.jsonl"
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        path.write_text("".join(json.dumps(row) + "\n" for row in rows if row["payload"].get("kind") != "runEnded"))
        run = self.result["native_runs"][1]
        run["artifacts"] = [self.artifact(self.root / item["path"]) for item in run["artifacts"]]
        self.assertEqual(run["exit_code"], 0)
        with self.assertRaisesRegex(Invalid, "native run is incomplete"):
            self.validate()


if __name__ == "__main__":
    unittest.main(verbosity=2)
