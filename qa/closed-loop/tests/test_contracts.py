import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import subprocess
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import contracts as c

SPEC = importlib.util.spec_from_file_location("zeus_closed_loop_runner", c.ROOT / "qa/closed-loop/run.py")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class MatrixContractTests(unittest.TestCase):
    def setUp(self):
        self.data = c.load(c.ROOT / "qa/feature-map.json")
        self.portable = runner.portable_module()

    def test_current_map_has_all_nineteen_requirements_and_real_case_bindings(self):
        checks = c.validate_map(self.data, self.portable)
        c.validate_registry(c.load(c.ROOT / "qa/regressions.json"), checks)
        self.assertEqual(len(self.data["features"]), 19)

    def test_deleting_a_checklist_item_cannot_make_full_gate_easier(self):
        self.data["features"].pop()
        with self.assertRaises(c.Invalid):
            c.validate_map(self.data, self.portable)

    def test_duplicate_ids_and_unknown_fields_are_rejected(self):
        for change in (lambda d: d["features"].append(d["features"][0]),
                       lambda d: d["features"][0].update(required=False),
                       lambda d: d["checks"][0].update(command=["true"])):
            data = copy.deepcopy(self.data)
            change(data)
            with self.assertRaises(c.Invalid):
                c.validate_map(data, self.portable)

    def test_every_feature_keeps_all_three_evidence_tiers(self):
        self.data["features"][0]["obligations"].pop()
        with self.assertRaises(c.Invalid):
            c.validate_map(self.data, self.portable)

    def test_missing_native_suite_and_missing_case_are_errors(self):
        data = copy.deepcopy(self.data)
        native = next(row for row in data["checks"] if row["kind"] == "native-fixture")
        native["suite"] = "InventedTests"
        with self.assertRaises(c.Invalid):
            c.validate_map(data, self.portable)
        data = copy.deepcopy(self.data)
        data["features"][0]["obligations"][0]["cases"][0]["function"] = "testThatDoesNotExist"
        with self.assertRaises(c.Invalid):
            c.validate_map(data, self.portable)

    def test_adding_portable_group_without_feature_binding_is_rejected(self):
        data = copy.deepcopy(self.data)
        data["checks"] = [x for x in data["checks"] if x.get("group") != "polyglot"]
        with self.assertRaises(c.Invalid):
            c.validate_map(data, self.portable)

    def test_removed_regression_guard_is_a_schema_failure(self):
        checks = c.validate_map(self.data, self.portable)
        ledger = c.load(c.ROOT / "qa/regressions.json")
        ledger["regressions"][0]["guard"]["function"] = "missingRegression"
        with self.assertRaises(c.Invalid):
            c.validate_registry(ledger, checks)

    def test_device_obligation_cannot_be_satisfied_by_native_fixture_kind(self):
        native = next(row for row in self.data["checks"] if row["kind"] == "native-fixture")
        native["tier"] = "device-proof"
        with self.assertRaises(c.Invalid):
            c.validate_map(self.data, self.portable)

    def test_pass_counts_do_not_turn_unimplemented_or_missing_obligations_green(self):
        checks = {row["id"]: {"status": "passed", "tests": 1000, "passed_functions": []}
                  for row in self.data["checks"] if row["kind"] == "portable"}
        results = c.evaluate_features(self.data, checks, Path("/tmp"))
        self.assertTrue(all(row["status"] == "incomplete" for row in results))
        self.assertTrue(any(o["status"] == "not-run" for row in results for o in row["obligations"]))


class EvidenceContractTests(unittest.TestCase):
    def test_swift_nonzero_empty_missing_or_ambiguous_summary_is_failure(self):
        passed = "✔ Test actualCase() passed after 0.1 seconds.\n✔ Test run with 1 test in 1 suite passed after 0.1 seconds.\n"
        self.assertEqual(c.swift_summary(passed, 0), (1, 1, ["actualCase"]))
        for text, code in [(passed, 1), ("", 0), (passed.replace("1 test", "0 tests"), 0),
                           (passed + passed, 0), (passed.replace("✔ Test actualCase() passed after 0.1 seconds.\n", ""), 0),
                           (passed + "✘ Test bad() failed\n", 0)]:
            with self.assertRaises(c.Invalid):
                c.swift_summary(text, code)

    def test_python_skips_and_zero_cases_do_not_pass(self):
        passed = "test_one (Suite.test_one) ... ok\nRan 1 test in 0.1s\nOK\n"
        self.assertEqual(runner.python_summary(passed, 0), (1, 1, ["test_one"]))
        for text in [passed.replace("OK", "OK (skipped=1)"), passed.replace("Ran 1 test", "Ran 0 tests"),
                     passed.replace("... ok", "... skipped")]:
            with self.assertRaises(c.Invalid):
                runner.python_summary(text, 0)

    def test_manifest_omission_hash_tampering_and_compiled_byte_tampering_fail(self):
        portable = runner.portable_module()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            actual = portable.prepare(root / "actual", "presentation")
            expected = portable.prepare(root / "expected", "presentation")
            c.manifest_matches(actual, expected)
            manifest = actual / "validation-manifest.json"
            original = manifest.read_bytes()
            data = c.load(manifest)
            data["files"].pop()
            manifest.write_text(json.dumps(data))
            with self.assertRaises(c.Invalid):
                c.manifest_matches(actual, expected)
            manifest.write_bytes(original)
            copied = actual / "Sources/ZeusCore/PortableExcerpts.swift"
            copied.write_text(copied.read_text() + "\n// changed compiled bytes\n")
            with self.assertRaises(c.Invalid):
                c.manifest_matches(actual, expected)

    def test_excerpt_case_outside_compiled_boundary_cannot_borrow_group_pass(self):
        portable = runner.portable_module()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            package = portable.prepare(output, "scribe")
            case = {"file": "Tests/ZeusCoreTests/ScribeLiveLogicTests.swift", "function": "inventedOutsideExcerpt"}
            row = {"status": "passed", "package": str(package.relative_to(output)), "passed_functions": [case["function"]]}
            with self.assertRaises(c.Invalid):
                c.case_passed(case, row, output)

    def test_same_named_test_in_another_file_cannot_lend_its_pass(self):
        portable = runner.portable_module()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            package = portable.prepare(output, "presentation")
            function = "lateWordTimingsCannotReviveACancelledDrawing"
            case = {"file": "Tests/ZeusCoreTests/SpeechTimelineTests.swift", "function": function}
            row = {"status": "passed", "package": "presentation", "passed_functions": [function]}
            c.case_passed(case, row, output)
            duplicate = package / "Tests/ZeusCoreTests/Duplicate.swift"
            duplicate.write_text(f"import Testing\nstruct Duplicate {{\n @Test func {function}() {{}}\n}}\n")
            with self.assertRaises(c.Invalid):
                c.case_passed(case, row, output)

    def test_ordinary_helper_is_not_an_executed_test_declaration(self):
        self.assertEqual(c.runnable_functions("struct A {\n func guardName() {}\n}"), [])
        self.assertEqual(c.runnable_functions("struct A {\n @MainActor @Test func guardName() {}\n}"), ["guardName"])

    def test_cross_host_receipt_normalizes_checkout_path_but_not_platform_or_code(self):
        portable = runner.portable_module()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            actual = portable.prepare(output / "a", "buddy", platform_name="darwin")
            expected = portable.prepare(output / "b", "buddy", platform_name="darwin")
            manifest = actual / "validation-manifest.json"
            data = c.load(manifest)
            data["repository"] = "/Users/runner/work/Zeus/Zeus"
            manifest.write_text(json.dumps(data))
            c.manifest_matches(actual, expected)
            linux = portable.prepare(output / "linux", "buddy", platform_name="linux")
            with self.assertRaises(c.Invalid):
                c.manifest_matches(actual, linux)

    def test_extra_versioned_package_manifest_cannot_change_compiled_recipe(self):
        portable = runner.portable_module()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            actual = portable.prepare(output / "a", "presentation")
            expected = portable.prepare(output / "b", "presentation")
            (actual / "Package@swift-6.0.swift").write_text("// different package\n")
            with self.assertRaises(c.Invalid):
                c.manifest_matches(actual, expected)

    def test_input_snapshot_detects_code_changes_and_excludes_archived_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "Sources").mkdir()
            source = root / "Sources/fixture.swift"
            source.write_text("let value = 1\n")
            output = root / "output"
            output.mkdir()
            before = c.source_snapshot(root, output)
            (output / "result.json").write_text("{}")
            (root / "docs").mkdir()
            (root / "docs/plan.md").write_text("evidence description")
            receipts = root / "qa/receipts/run"
            receipts.mkdir(parents=True)
            (receipts / "result.json").write_text("{}")
            self.assertEqual(c.source_snapshot(root, output), before)
            source.write_text("let value = 2\n")
            self.assertNotEqual(c.source_snapshot(root, output), before)

    def test_duplicate_json_keys_cannot_overwrite_failure_with_success(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "receipt.json"
            file.write_text('{"status":"failed","status":"passed"}')
            with self.assertRaises(c.Invalid):
                c.load(file)

    def test_test_paths_cannot_escape_repository(self):
        for path in ["../secret.swift", "/tmp/secret.swift", "Tests\\secret.swift"]:
            with self.assertRaises(c.Invalid):
                c.relative_file(path)

    def test_timeout_or_missing_tool_is_failed_command_with_log(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "tool.log"
            code, _ = runner.execute(["/zeus/no-such-executable"], log, 1)
            self.assertEqual(code, 127)
            self.assertIn("COULD NOT START", log.read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
