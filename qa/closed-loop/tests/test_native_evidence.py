"""Wire-v0 lifecycle fixtures; these tests do not claim native app execution."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import subprocess
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import native_evidence as n
from contracts import Invalid, digest, source_snapshot


class NativeEventEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        self.source = self.repo / "Tests/ZeusCoreTests/SampleTests.swift"
        self.source.parent.mkdir(parents=True)
        self.source.write_text("import Testing\nstruct SampleTests {\n    @Test func example() {}\n}\n")
        self.definitions = [{"kind": "native-module", "module": "ZeusCoreTests"}]
        self.suite = "ZeusCoreTests.SampleTests"
        self.ident = self.suite + "/example()/SampleTests.swift:3:6"
        self.payload = {"kind": "function", "id": self.ident, "name": "example()", "isParameterized": False,
                        "sourceLocation": {"_filePath": str(self.source), "fileID": "ZeusCoreTests/SampleTests.swift", "line": 3, "column": 6}}
        self.declarations = [{"kind": "test", "version": 0, "payload": {"kind": "suite", "id": self.suite}},
                             {"kind": "test", "version": 0, "payload": self.payload}]

    def event(self, kind, ident=None, symbol=None, case=None):
        payload = {"kind": kind, "messages": [{"symbol": symbol, "text": "synthetic protocol fixture"}] if symbol else []}
        if ident is not None:
            payload["testID"] = ident
        if case is not None:
            payload["_testCase"] = {"id": case}
        return {"kind": "event", "version": 0, "payload": payload}

    def events(self):
        rows = copy.deepcopy(self.declarations) + [self.event("runStarted"), self.event("testStarted", self.suite), self.event("testStarted", self.ident)]
        for case in self.payload.get("_testCases", []):
            rows += [self.event("testCaseStarted", self.ident, case=case["id"]), self.event("testCaseEnded", self.ident, case=case["id"])]
        return rows + [self.event("testEnded", self.ident, "pass"), self.event("testEnded", self.suite, "pass"), self.event("runEnded", symbol="pass")]

    def write(self, name, rows):
        path = self.repo / name
        path.write_text("".join(json.dumps(row) + "\n" for row in rows))
        return path

    def compiled(self):
        return n.discovery(self.write("discovery.jsonl", self.declarations), self.definitions, self.repo)

    def verify(self, rows):
        return n.execution(self.write("events.jsonl", rows), self.compiled(), self.definitions, self.repo)

    def parameterize(self):
        self.source.write_text("import Testing\nstruct SampleTests {\n    @Test(arguments: [1, 2]) func example(_ value: Int) {}\n}\n")
        self.ident = self.suite + "/example(_:)/SampleTests.swift:3:6"
        self.payload.update(id=self.ident, name="example(_:)", isParameterized=True,
                            _testCases=[{"id": "argument-one"}, {"id": "argument-two"}])

    def test_complete_qualified_execution_binds_exact_file_and_function(self):
        metrics = self.verify(self.events())
        self.assertEqual((metrics["tests"], metrics["suites"]), (1, 1))
        n.case_passed({"file": "Tests/ZeusCoreTests/SampleTests.swift", "function": "example"}, metrics["passed_cases"])
        with self.assertRaises(Invalid):
            n.case_passed({"file": "Tests/ZeusCoreTests/OtherTests.swift", "function": "example"}, metrics["passed_cases"])

    def test_positive_summary_cannot_hide_skipped_or_issue_events(self):
        for kind in ["testSkipped", "issueRecorded"]:
            with self.subTest(kind=kind), self.assertRaises(Invalid):
                self.verify(self.events()[:-1] + [self.event(kind, self.ident), self.event("runEnded", symbol="pass")])

    def test_omitted_compiled_function_or_unfinished_run_fails(self):
        rows = self.events()
        for bad in [rows[:-1], [row for row in rows if row["payload"].get("kind") != "testEnded"],
                    [row for row in rows if row["payload"].get("testID") != self.ident]]:
            with self.assertRaises(Invalid):
                self.verify(bad)

    def test_duplicate_lifecycle_and_unknown_identity_cannot_replace_a_missing_case(self):
        for event in [self.event("testStarted", self.ident), self.event("testEnded", self.ident, "pass"),
                      self.event("testStarted", "ZeusCoreTests.Other/example()/Other.swift:3:6")]:
            with self.assertRaises(Invalid):
                self.verify(self.events()[:-1] + [event, self.event("runEnded", symbol="pass")])

    def test_compiled_core_discovery_must_include_every_current_declaration(self):
        self.source.write_text(self.source.read_text().replace("\n}", "\n    @Test func omitted() {}\n}"))
        with self.assertRaises(Invalid):
            self.compiled()

    def test_source_path_line_and_qualified_id_must_agree(self):
        original = copy.deepcopy(self.payload)
        mutations = [lambda p: p["sourceLocation"].update(_filePath="/unrelated/SampleTests.swift"),
                     lambda p: p["sourceLocation"].update(line=2),
                     lambda p: p.update(id=p["id"].replace("example()", "borrowed()")),
                     lambda p: p["sourceLocation"].update(fileID="ZeusCoreTests/../SampleTests.swift")]
        for change in mutations:
            self.payload.clear(); self.payload.update(copy.deepcopy(original)); change(self.payload)
            with self.assertRaises(Invalid):
                self.compiled()

    def test_parameterized_execution_requires_every_discovered_argument_identity(self):
        self.parameterize()
        self.assertEqual(self.verify(self.events())["parameter_cases"], 2)
        without_second = [row for row in self.events() if row["payload"].get("_testCase", {}).get("id") != "argument-two"]
        with self.assertRaises(Invalid):
            self.verify(without_second)

    def test_zero_duplicate_or_invented_parameter_cases_fail(self):
        self.parameterize()
        for cases in [[], [{"id": "same"}, {"id": "same"}]]:
            self.payload["_testCases"] = cases
            with self.assertRaises(Invalid):
                self.compiled()
        self.payload["_testCases"] = [{"id": "argument-one"}, {"id": "argument-two"}]
        rows = self.events(); rows.insert(-3, self.event("testCaseStarted", self.ident, case="invented"))
        with self.assertRaises(Invalid):
            self.verify(rows)

    def test_protocol_version_and_duplicate_json_keys_fail_closed(self):
        for version in [1, True, "0"]:
            rows = copy.deepcopy(self.declarations); rows[0]["version"] = version
            with self.assertRaises(Invalid):
                n.discovery(self.write("bad-version.jsonl", rows), self.definitions, self.repo)
        path = self.repo / "duplicate.jsonl"
        path.write_text('{"kind":"test","payload":{},"version":1,"version":0}\n')
        with self.assertRaises(Invalid):
            n.stream(path)

    def test_execution_cannot_borrow_or_change_a_compiled_declaration(self):
        rows = self.events(); rows[1]["payload"]["sourceLocation"]["column"] = 7
        with self.assertRaises(Invalid):
            self.verify(rows)

    def test_unselected_suite_execution_cannot_hide_behind_complete_selected_tests(self):
        other = "ZeusAppTests.UnreviewedTests"
        self.declarations.append({"kind": "test", "version": 0, "payload": {"kind": "suite", "id": other}})
        rows = self.events()[:-1] + [self.event("testStarted", other), self.event("testEnded", other, "pass"), self.event("runEnded", symbol="pass")]
        with self.assertRaises(Invalid):
            self.verify(rows)

    def test_terminal_run_rejects_late_declarations_and_missing_suite_lifecycle(self):
        rows = self.events()
        late = rows + [copy.deepcopy(self.declarations[0])]
        missing_suite = [row for row in rows if row["payload"].get("testID") != self.suite]
        for malformed in (late, missing_suite):
            with self.subTest(rows=malformed), self.assertRaises(Invalid):
                self.verify(malformed)

    def test_only_reviewed_module_and_exact_app_suite_filters_are_allowed(self):
        self.assertEqual(n.selector(self.definitions), r"^ZeusCoreTests(?:\.|/)")
        with self.assertRaises(Invalid):
            n.selector([{"kind": "native-module", "module": "ZeusAppTests"}])
        with self.assertRaises(Invalid):
            n.selector(self.definitions * 2)

    def receipt(self):
        """Complete synthetic file-backed receipt, not an app-run claim."""
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        (self.repo / "qa").mkdir()
        (self.repo / "qa/feature-map.json").write_text('{"features": []}')
        (self.repo / "qa/regressions.json").write_text('{"regressions": []}')
        output = self.repo / "evidence"
        for folder in ["native-build", "native-discovery", "native-all"]:
            (output / folder).mkdir(parents=True)
        (output / "native-build/build.log").write_text("Build complete! (0.1s)\n")
        (output / "native-discovery/test.log").write_text(self.ident + "\n")
        (output / "native-discovery/events.jsonl").write_text("".join(json.dumps(x) + "\n" for x in self.declarations))
        (output / "native-all/events.jsonl").write_text("".join(json.dumps(x) + "\n" for x in self.events()))
        (output / "native-all/test.log").write_text("✔ Test example() passed after 0.1 seconds.\n✔ Test run with 1 test in 1 suite passed after 0.1 seconds.\n")
        manifest = source_snapshot(self.repo, output)
        (output / "source-manifest.json").write_text(json.dumps(manifest))
        def evidence(path):
            return {"path": path, "sha256": digest((output / path).read_bytes())}
        metrics = self.verify(self.events())
        # verify() creates files outside the chosen evidence folder; refresh the
        # current-source manifest to include those real fixture inputs as well.
        manifest = source_snapshot(self.repo, output)
        (output / "source-manifest.json").write_text(json.dumps(manifest))
        result = {"schema_version": 1, "status": "passed", "tested_sha": "a" * 40, "head_sha": "b" * 40,
                  "repository": str(self.repo), "output_directory": str(output), "platform": "darwin", "errors": [],
                  "source_snapshot_sha256": manifest["sha256"], "source_manifest": evidence("source-manifest.json"),
                  "map_sha256": digest((self.repo / "qa/feature-map.json").read_bytes()),
                  "registry_sha256": digest((self.repo / "qa/regressions.json").read_bytes()),
                  "native_build": {"status": "passed", "command": ["swift", "build", "--build-tests", "--jobs", "2"],
                                   "exit_code": 0, "source_snapshot_sha256": manifest["sha256"], "duration_seconds": 0.1,
                                   "artifacts": [evidence("native-build/build.log")]},
                  "native_discovery": {"status": "passed", "command": n.discovery_command(output), "exit_code": 0,
                                       "source_snapshot_sha256": manifest["sha256"], "duration_seconds": 0.1,
                                       "artifacts": [evidence("native-discovery/test.log"), evidence("native-discovery/events.jsonl")]},
                  "native_run": {"id": "native-all", "kind": "native-combined", "status": "passed", "exit_code": 0,
                                 "command": n.run_command(self.definitions, 2, output, "native-all"), **metrics,
                                 "passed_functions": ["example"],
                                 "artifacts": [evidence("native-all/test.log"), evidence("native-all/events.jsonl")]}}
        (output / "result.json").write_text(json.dumps(result))
        return output, result

    def test_complete_file_backed_receipt_recomputes_events_and_current_source(self):
        output, _ = self.receipt()
        definitions = [{**self.definitions[0], "id": "native-ZeusCoreTests"}]
        metrics = n.validate_receipt(output, "a" * 40, "b" * 40, definitions, self.repo)
        self.assertEqual(metrics["tests"], 1)
        self.source.write_text(self.source.read_text() + "// changed input\n")
        with self.assertRaises(Invalid):
            n.validate_receipt(output, "a" * 40, "b" * 40, definitions, self.repo)

    def test_changed_events_or_foreign_commit_cannot_use_successful_console_output(self):
        output, _ = self.receipt()
        definitions = [{**self.definitions[0], "id": "native-ZeusCoreTests"}]
        with self.assertRaises(Invalid):
            n.validate_receipt(output, "c" * 40, "b" * 40, definitions, self.repo)
        (output / "native-all/events.jsonl").write_text("{}\n")
        with self.assertRaises(Invalid):
            n.validate_receipt(output, "a" * 40, "b" * 40, definitions, self.repo)


if __name__ == "__main__":
    unittest.main(verbosity=2)
