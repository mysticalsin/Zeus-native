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

    def empty_run(self, symbol="pass", tests=0):
        ended = self.event("runEnded", symbol=symbol)
        ended["payload"]["messages"][0]["text"] = f"Test run with {tests} tests in 0 suites passed after 0.001 seconds."
        return [self.event("runStarted"), ended]

    def test_a_leading_empty_run_still_verifies_the_selected_tests(self):
        try:
            metrics = self.verify(self.empty_run() + self.events())
        except Invalid as error:
            self.fail(str(error))
        self.assertEqual((metrics["tests"], metrics["suites"]), (1, 1))
        n.case_passed({"file": "Tests/ZeusCoreTests/SampleTests.swift", "function": "example"}, metrics["passed_cases"])

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

    def test_list_discovery_without_argument_expansion_requires_a_complete_prerun_case_plan(self):
        self.parameterize()
        declarations = copy.deepcopy(self.declarations)
        declarations[1]["payload"].pop("_testCases")
        compiled = n.discovery(self.write("list.jsonl", declarations), self.definitions, self.repo)
        def verify(rows):
            return n.execution(self.write("planned.jsonl", rows), compiled, self.definitions, self.repo)
        self.assertEqual(verify(self.events())["parameter_cases"], 2)
        missing_plan = self.events()
        missing_plan[1]["payload"].pop("_testCases")
        missing_case = [row for row in self.events() if row["payload"].get("_testCase", {}).get("id") != "argument-two"]
        late_plan = self.events()
        declaration = late_plan.pop(1)
        late_plan.insert(2, declaration)
        for malformed in (missing_plan, missing_case, late_plan):
            with self.assertRaises(Invalid):
                verify(malformed)

    def test_implicit_suite_must_be_the_selected_compiled_function_container(self):
        compiled = n.discovery(self.write("implicit.jsonl", self.declarations[1:]), self.definitions, self.repo)
        self.assertEqual(n.execution(self.write("implicit-run.jsonl", self.events()), compiled,
                                     self.definitions, self.repo)["suites"], 1)
        invented = self.events()
        invented[0]["payload"]["id"] = "ZeusCoreTests.ForeignContainer"
        with self.assertRaises(Invalid):
            n.execution(self.write("invented-suite.jsonl", invented), compiled, self.definitions, self.repo)

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
        for folder in ["native-build", "native-discovery", "native-ZeusCoreTests"]:
            (output / folder).mkdir(parents=True)
        (output / "native-build/build.log").write_text("Build complete! (0.1s)\n")
        (output / "native-discovery/test.log").write_text(self.ident + "\n")
        (output / "native-discovery/events.jsonl").write_text("".join(json.dumps(x) + "\n" for x in self.declarations))
        (output / "native-ZeusCoreTests/events.jsonl").write_text("".join(json.dumps(x) + "\n" for x in self.events()))
        (output / "native-ZeusCoreTests/test.log").write_text("✔ Test example() passed after 0.1 seconds.\n✔ Test run with 1 test in 1 suite passed after 0.1 seconds.\n")
        manifest = source_snapshot(self.repo, output)
        (output / "source-manifest.json").write_text(json.dumps(manifest))
        def evidence(path):
            return {"path": path, "sha256": digest((output / path).read_bytes())}
        metrics = self.verify(self.events())
        # verify() creates files outside the chosen evidence folder; refresh the
        # current-source manifest to include those real fixture inputs as well.
        manifest = source_snapshot(self.repo, output)
        (output / "source-manifest.json").write_text(json.dumps(manifest))
        result = {"schema_version": 2, "status": "passed", "tested_sha": "a" * 40, "head_sha": "b" * 40,
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
                  "native_summary": metrics,
                  "native_runs": [{"id": "native-ZeusCoreTests", "kind": "native-module", "status": "passed", "exit_code": 0,
                                   "tier": "native-integration", "scope": "Synthetic receipt fixture only.",
                                 "command": n.run_command(self.definitions, 2, output, "native-ZeusCoreTests"), **metrics,
                                 "passed_functions": ["example"],
                                 "artifacts": [evidence("native-ZeusCoreTests/test.log"), evidence("native-ZeusCoreTests/events.jsonl")]}]}
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

    def test_listing_recovers_tests_a_later_product_dropped_from_the_event_stream(self):
        # Captured `swift test list` stdout. The event stream kept only the last product.
        self.source.write_text("import Testing\nstruct SampleTests {\n    @Test func example() {}\n"
                               "    @Test(arguments: [1, 2]) func counted(_ value: Int) {}\n}\n"
                               "struct Outer {\n    @Suite struct NestedTests {\n        @Test func inside() {}\n    }\n}\n")
        app = self.repo / "Tests/ZeusAppTests/AppMarkTests.swift"
        legacy = self.repo / "Tests/ZeusAppTests/AppLegacyTests.swift"
        app.parent.mkdir(parents=True)
        app.write_text("import Testing\nstruct AppMarkTests {\n    @Test func shows() {}\n}\n")
        legacy.write_text("import XCTest\nfinal class AppLegacyTests: XCTestCase {\n    func testLegacy() {}\n}\n")
        shows = {"kind": "function", "id": "ZeusAppTests.AppMarkTests/shows()/AppMarkTests.swift:3:6",
                 "name": "shows()", "isParameterized": False,
                 "sourceLocation": {"_filePath": str(app), "fileID": "ZeusAppTests/AppMarkTests.swift", "line": 3, "column": 6}}
        folder = self.repo / "native-discovery"
        folder.mkdir()
        events = folder / "events.jsonl"
        events.write_text("".join(json.dumps(row) + "\n" for row in [
            {"kind": "test", "version": 0, "payload": {"kind": "suite", "id": "ZeusAppTests.AppMarkTests"}},
            {"kind": "test", "version": 0, "payload": shows},
        ]))
        (folder / "test.log").write_text("\n".join([
            "ZeusAppTests.AppLegacyTests/testLegacy",
            "ZeusCoreTests.Outer/NestedTests/inside()",
            "ZeusCoreTests.SampleTests/counted(_:)",
            "ZeusCoreTests.SampleTests/example()",
            "ZeusAppTests.AppMarkTests/shows()",
            "",
        ]))
        definitions = [{"kind": "native-module", "module": "ZeusCoreTests"},
                       {"kind": "native-fixture", "id": "native-AppMarkTests", "suite": "AppMarkTests",
                        "file": "Tests/ZeusAppTests/AppMarkTests.swift"},
                       {"kind": "native-fixture", "id": "native-AppLegacyTests", "suite": "AppLegacyTests",
                        "file": "Tests/ZeusAppTests/AppLegacyTests.swift"}]
        try:
            compiled = n.discovery(events, definitions, self.repo)
        except Invalid as error:
            self.fail(str(error))
        found = {(row["file"], row["function"], row["parameterized"]) for row in compiled["functions"].values()}
        self.assertEqual(found, {
            ("Tests/ZeusCoreTests/SampleTests.swift", "example", False),
            ("Tests/ZeusCoreTests/SampleTests.swift", "counted", True),
            ("Tests/ZeusCoreTests/SampleTests.swift", "inside", False),
            ("Tests/ZeusAppTests/AppMarkTests.swift", "shows", False),
            ("Tests/ZeusAppTests/AppLegacyTests.swift", "testLegacy", False),
        })
        self.assertIn("ZeusCoreTests.Outer/NestedTests/inside()/SampleTests.swift:8:10", compiled["functions"])
        self.assertIn("ZeusCoreTests.SampleTests/example()/SampleTests.swift:3:6", compiled["functions"])
        self.assertIn("ZeusCoreTests.SampleTests/counted(_:)/SampleTests.swift:4:6", compiled["functions"])

    def _events_beside(self):
        folder = self.repo / "native-discovery"
        folder.mkdir()
        events = folder / "events.jsonl"
        events.write_text("".join(json.dumps(row) + "\n" for row in self.declarations))
        return events, folder

    def test_a_repeated_stdout_line_is_stored_once(self):
        # The second copy must not be kept under a different id. A set of files would hide that.
        self._prepare_recovered_sources()
        shows = {"kind": "function", "id": "ZeusAppTests.AppMarkTests/shows()/AppMarkTests.swift:3:6",
                 "name": "shows()", "isParameterized": False,
                 "sourceLocation": {"_filePath": str(self.repo / "Tests/ZeusAppTests/AppMarkTests.swift"),
                                    "fileID": "ZeusAppTests/AppMarkTests.swift", "line": 3, "column": 6}}
        folder = self.repo / "native-discovery"
        folder.mkdir()
        events = folder / "events.jsonl"
        events.write_text("".join(json.dumps(row) + "\n" for row in [
            {"kind": "test", "version": 0, "payload": {"kind": "suite", "id": "ZeusAppTests.AppMarkTests"}},
            {"kind": "test", "version": 0, "payload": shows},
        ]))
        (folder / "test.log").write_text("\n".join([
            "ZeusAppTests.AppLegacyTests/testLegacy",
            "ZeusAppTests.AppLegacyTests/testLegacy",
            "ZeusCoreTests.Outer/NestedTests/inside()",
            "ZeusCoreTests.SampleTests/counted(_:)",
            "ZeusCoreTests.SampleTests/example()",
            "ZeusAppTests.AppMarkTests/shows()",
        ]) + "\n")
        compiled = n.discovery(events, self._recovered_definitions(), self.repo)
        self.assertEqual(sorted(compiled["functions"]), [
            "ZeusAppTests.AppLegacyTests/testLegacy/AppLegacyTests.swift:3:6",
            "ZeusAppTests.AppMarkTests/shows()/AppMarkTests.swift:3:6",
            "ZeusCoreTests.Outer/NestedTests/inside()/SampleTests.swift:8:10",
            "ZeusCoreTests.SampleTests/counted(_:)/SampleTests.swift:4:6",
            "ZeusCoreTests.SampleTests/example()/SampleTests.swift:3:6",
        ])
        self.assertEqual(len(compiled["functions"]), 5)

    def test_a_listing_line_from_another_product_is_ignored(self):
        events, folder = self._events_beside()
        (folder / "test.log").write_text("OtherProduct.ForeignTests/foreign()\nZeusCoreTests.SampleTests/example()\n")
        compiled = n.discovery(events, self.definitions, self.repo)
        self.assertEqual(sorted(compiled["functions"]), [self.ident])
        self.assertEqual(len(compiled["functions"]), 1)

    def test_a_listing_line_that_does_not_bind_raises(self):
        events, folder = self._events_beside()
        (folder / "test.log").write_text("ZeusCoreTests.SampleTests/missing()\nZeusCoreTests.SampleTests/example()\n")
        with self.assertRaises(Invalid) as caught:
            n.discovery(events, self.definitions, self.repo)
        self.assertIn("does not bind to one current declaration", str(caught.exception))
        self.assertIn("ZeusCoreTests.SampleTests/missing()", str(caught.exception))

    def test_an_empty_listing_keeps_the_event_stream(self):
        events, folder = self._events_beside()
        (folder / "test.log").write_text("")
        compiled = n.discovery(events, self.definitions, self.repo)
        self.assertEqual(sorted(compiled["functions"]), [self.ident])
        self.assertEqual(len(compiled["functions"]), 1)

    def test_a_symlinked_listing_is_not_read(self):
        events, folder = self._events_beside()
        target = self.repo / "redirected.log"
        target.write_text("ZeusCoreTests.SampleTests/missing()\n")
        (folder / "test.log").symlink_to(target)
        compiled = n.discovery(events, self.definitions, self.repo)
        self.assertEqual(sorted(compiled["functions"]), [self.ident])
        self.assertEqual(len(compiled["functions"]), 1)

    def test_an_xctest_listing_line_records_its_func_line_and_column(self):
        legacy = self.repo / "Tests/ZeusAppTests/AppLegacyTests.swift"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("import XCTest\nfinal class AppLegacyTests: XCTestCase {\n    func testLegacy() {}\n}\n")
        events, folder = self._events_beside()
        (folder / "test.log").write_text("ZeusAppTests.AppLegacyTests/testLegacy\n")
        definitions = self.definitions + [{"kind": "native-fixture", "id": "native-AppLegacyTests", "suite": "AppLegacyTests",
                                           "file": "Tests/ZeusAppTests/AppLegacyTests.swift"}]
        compiled = n.discovery(events, definitions, self.repo)
        ident = "ZeusAppTests.AppLegacyTests/testLegacy/AppLegacyTests.swift:3:6"
        self.assertEqual(sorted(compiled["functions"]), [ident, self.ident])
        self.assertEqual(compiled["functions"][ident]["line"], 3)
        self.assertEqual(compiled["functions"][ident]["column"], 6)
        self.assertEqual(len(compiled["functions"]), 2)

    def _prepare_recovered_sources(self):
        self.source.write_text("import Testing\nstruct SampleTests {\n    @Test func example() {}\n"
                               "    @Test(arguments: [1, 2]) func counted(_ value: Int) {}\n}\n"
                               "struct Outer {\n    @Suite struct NestedTests {\n        @Test func inside() {}\n    }\n}\n")
        app = self.repo / "Tests/ZeusAppTests/AppMarkTests.swift"
        legacy = self.repo / "Tests/ZeusAppTests/AppLegacyTests.swift"
        app.parent.mkdir(parents=True)
        app.write_text("import Testing\nstruct AppMarkTests {\n    @Test func shows() {}\n}\n")
        legacy.write_text("import XCTest\nfinal class AppLegacyTests: XCTestCase {\n    func testLegacy() {}\n}\n")

    def _recovered_definitions(self):
        return [{"kind": "native-module", "module": "ZeusCoreTests"},
                {"kind": "native-fixture", "id": "native-AppMarkTests", "suite": "AppMarkTests",
                 "file": "Tests/ZeusAppTests/AppMarkTests.swift"},
                {"kind": "native-fixture", "id": "native-AppLegacyTests", "suite": "AppLegacyTests",
                 "file": "Tests/ZeusAppTests/AppLegacyTests.swift"}]

    def test_changed_events_or_foreign_commit_cannot_use_successful_console_output(self):
        output, _ = self.receipt()
        definitions = [{**self.definitions[0], "id": "native-ZeusCoreTests"}]
        with self.assertRaises(Invalid):
            n.validate_receipt(output, "c" * 40, "b" * 40, definitions, self.repo)
        (output / "native-ZeusCoreTests/events.jsonl").write_text("{}\n")
        with self.assertRaises(Invalid):
            n.validate_receipt(output, "a" * 40, "b" * 40, definitions, self.repo)


if __name__ == "__main__":
    unittest.main(verbosity=2)
