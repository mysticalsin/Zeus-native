import copy
import importlib.util
import json
import re
from pathlib import Path
import sys
import tempfile
import subprocess
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import contracts as c
import native_evidence

SPEC = importlib.util.spec_from_file_location("zeus_closed_loop_runner", c.ROOT / "qa/closed-loop/run.py")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class MatrixContractTests(unittest.TestCase):
    def setUp(self):
        self.data = c.load(c.ROOT / "qa/feature-map.json")
        self.portable = runner.portable_module()

    def test_current_map_has_all_twentyone_requirements_and_real_case_bindings(self):
        checks = c.validate_map(self.data, self.portable)
        c.validate_registry(c.load(c.ROOT / "qa/regressions.json"), checks)
        self.assertEqual(len(self.data["features"]), 21)

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
        checks = {check["id"]: check for check in self.data["checks"]}
        for index, feature in enumerate(self.data["features"]):
            for tier in ("contract", "native-integration", "device-proof"):
                with self.subTest(feature=feature["id"], missing_tier=tier):
                    data = copy.deepcopy(self.data)
                    data["features"][index]["obligations"] = [
                        row for row in feature["obligations"] if checks[row["check"]]["tier"] != tier]
                    with self.assertRaisesRegex(c.Invalid, feature["id"] + " needs contract, native integration, and device proof"):
                        c.validate_map(data, self.portable)

    def test_a_suite_nested_in_a_serialized_parent_is_named_parent_slash_suite(self):
        # Swift Testing reports a nested suite as Module.Parent/Suite/test(); the map names it the same way.
        checks = c.validate_map(self.data, self.portable)
        fit = checks["native-ScribeMeetingCardFitTests"]
        self.assertEqual(fit["suite"], "ScribeMeetingCardHosted/ScribeMeetingCardFitTests")
        self.assertRegex("ZeusAppTests.ScribeMeetingCardHosted/ScribeMeetingCardFitTests/fit()",
                         native_evidence.selector([fit]))
        for bad in ("WrongParent/ScribeMeetingCardFitTests", "ScribeMeetingCardHosted/InventedTests",
                    "A/B/ScribeMeetingCardFitTests", "ScribeMeetingCardHosted/"):
            data = copy.deepcopy(self.data)
            next(row for row in data["checks"] if row["id"] == fit["id"])["suite"] = bad
            with self.assertRaises(c.Invalid, msg=bad):
                c.validate_map(data, self.portable)

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


class TrustedNativeFixtureTests(unittest.TestCase):
    ID = "device-ScribeTrustedAccessibilityJourneyTests"

    def setUp(self):
        self.data = c.load(c.ROOT / "qa/feature-map.json")
        self.portable = runner.portable_module()

    def trusted(self, data=None):
        return next(row for row in (data or self.data)["checks"] if row["id"] == self.ID)

    def test_ax_journey_is_bound_to_the_trusted_kind_and_regressions_stay_executable(self):
        checks = c.validate_map(self.data, self.portable)
        self.assertEqual((checks[self.ID]["kind"], checks[self.ID]["tier"]), ("trusted-native-fixture", "device-proof"))
        ledger = c.validate_registry(c.load(c.ROOT / "qa/regressions.json"), checks)
        self.assertEqual({row["id"] for row in ledger if row["check"] == self.ID}, {"REG-046", "REG-140"})

    def test_trusted_kind_is_never_selected_by_the_ci_app_job(self):
        import gate
        import native_evidence as native
        checks = c.validate_map(self.data, self.portable)
        self.assertNotIn("trusted-native-fixture", native.NATIVE_KINDS)
        self.assertNotIn("ScribeTrustedAccessibilityJourneyTests", gate.native_filter())
        selection = [row for row in checks.values() if row["kind"] in native.NATIVE_KINDS]
        self.assertFalse(any(native.selected("ZeusAppTests.ScribeTrustedAccessibilityJourneyTests/x()/F.swift:1:1", [row])
                             for row in selection))
        with self.assertRaises(c.Invalid):
            native.partitions(selection + [checks[self.ID]])

    def test_trusted_kind_keeps_native_fixture_field_and_tier_rules(self):
        for change in (lambda row: row.update(tier="native-integration"), lambda row: row.update(extra="x"),
                       lambda row: row.update(suite="InventedTests"), lambda row: row.pop("file"),
                       lambda row: row.update(file="Tests/ZeusCoreTests/ScribeTests.swift")):
            data = copy.deepcopy(self.data)
            change(self.trusted(data))
            with self.subTest(change=change), self.assertRaises(c.Invalid):
                c.validate_map(data, self.portable)

    def test_trusted_obligation_cases_and_guards_must_live_in_its_file(self):
        data = copy.deepcopy(self.data)
        obligation = next(o for f in data["features"] for o in f["obligations"] if o["check"] == self.ID)
        obligation["cases"][0]["file"] = "Tests/ZeusAppTests/ScribeComponentJourneyTests.swift" \
            if obligation["cases"][0]["file"] != "Tests/ZeusAppTests/ScribeComponentJourneyTests.swift" else "Tests/ZeusAppTests/OwnedWindowEventDriver.swift"
        with self.assertRaises(c.Invalid):
            c.validate_map(data, self.portable)
        checks = c.validate_map(self.data, self.portable)
        ledger = c.load(c.ROOT / "qa/regressions.json")
        row = next(r for r in ledger["regressions"] if r["check"] == self.ID)
        row["guard"]["file"] = "qa/closed-loop/tests/test_gate.py"
        row["guard"]["function"] = "test_complete_current_revision_evidence_passes"
        with self.assertRaises(c.Invalid):
            c.validate_registry(ledger, checks)

    def test_runner_reports_not_run_in_development_and_blocked_in_full_without_executing(self):
        definition = self.trusted()
        for mode, status in (("development", "not-run"), ("full", "blocked")):
            with self.subTest(mode=mode), patch.object(runner, "execute", side_effect=AssertionError("must not execute")):
                row = runner.run_check(definition, SimpleNamespace(mode=mode, jobs=1, timeout=1), Path("/nonexistent"), None)
                self.assertEqual((row["status"], row["command"], row["exit_code"], row["artifacts"]), (status, [], None, []))
                self.assertTrue(row["reason"])


class EvidenceContractTests(unittest.TestCase):
    def test_swift_nonzero_empty_missing_or_ambiguous_summary_is_failure(self):
        passed = "✔ Test actualCase() passed after 0.1 seconds.\n✔ Test run with 1 test in 1 suite passed after 0.1 seconds.\n"
        self.assertEqual(c.swift_summary(passed, 0), (1, 1, ["actualCase"]))
        for text, code in [(passed, 1), ("", 0), (passed.replace("1 test", "0 tests"), 0),
                           (passed + passed, 0), (passed.replace("✔ Test actualCase() passed after 0.1 seconds.\n", ""), 0),
                           (passed + "✘ Test bad() failed\n", 0)]:
            with self.assertRaises(c.Invalid):
                c.swift_summary(text, code)

    def test_torn_portable_pointing_log_marks_required_cases_not_run(self):
        # Exact portable-pointing test.log from artifact 14448317026 (run 44344835181).
        # Stdout lines were torn, so the text parser never sees these pass lines.
        log = (Path(__file__).resolve().parent / "fixtures" / "portable-pointing-44344835181.log").read_text()
        _, _, functions = c.swift_summary(log, 0)
        check = {"status": "passed", "passed_functions": functions}
        for name in ("holdStartsImmediately", "oneXDisplayWithANegativeOrigin"):
            with self.assertRaises(c.Invalid) as caught:
                c.case_passed({"file": "Tests/ZeusCoreTests/PointingKeyGestureTests.swift", "function": name}, check, Path("/unused"))
            self.assertIn(f"required case did not run: {name}", str(caught.exception))

    def test_structured_results_keep_cases_the_torn_log_dropped(self):
        text = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="TestResults" errors="0" tests="2" failures="0" skipped="0" time="0.001">
    <testcase classname="PointingKeyGestureTests" name="holdStartsImmediately()" time="0.001" />
    <testcase classname="PointingOverlayGeometryTests" name="oneXDisplayWithANegativeOrigin()" time="0.001" />
  </testsuite>
</testsuites>
"""
        count, suites, functions = c.swift_structured_results(text, 0)
        self.assertEqual((count, suites), (2, 1))
        self.assertEqual(functions, ["holdStartsImmediately", "oneXDisplayWithANegativeOrigin"])
        failed = text.replace('name="holdStartsImmediately()" time="0.001" />',
                              'name="holdStartsImmediately()" time="0.001"><failure message="no">x</failure></testcase>')
        with self.assertRaises(c.Invalid):
            c.swift_structured_results(failed, 0)
        skipped = text.replace(
            '<testcase classname="PointingOverlayGeometryTests" name="oneXDisplayWithANegativeOrigin()" time="0.001" />',
            '<testcase classname="PointingOverlayGeometryTests" name="oneXDisplayWithANegativeOrigin()" time="0.001"><skipped /></testcase>')
        with self.assertRaises(c.Invalid):
            c.swift_structured_results(skipped, 0)

    def test_structured_results_fail_closed_when_a_required_case_is_missing(self):
        text = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="TestResults" errors="0" tests="1" failures="0" skipped="0" time="0.001">
    <testcase classname="PointingKeyGestureTests" name="holdStartsImmediately()" time="0.001" />
  </testsuite>
</testsuites>
"""
        _, _, functions = c.swift_structured_results(text, 0)
        run = (c.ROOT / "qa/closed-loop/run.py").read_text()
        gate = (c.ROOT / "qa/closed-loop/gate.py").read_text()
        self.assertIn("--xunit-output", run)
        self.assertIn("swift_structured_results", run)
        self.assertIn("swift_structured_results", gate)
        check = {"status": "passed", "passed_functions": functions}
        c.case_passed({"file": "Tests/ZeusCoreTests/PointingKeyGestureTests.swift", "function": "holdStartsImmediately"}, check, Path("/unused"))
        with self.assertRaises(c.Invalid) as caught:
            c.case_passed({"file": "Tests/ZeusCoreTests/PointingOverlayGeometryTests.swift", "function": "oneXDisplayWithANegativeOrigin"}, check, Path("/unused"))
        self.assertIn("required case did not run: oneXDisplayWithANegativeOrigin", str(caught.exception))

    def test_structured_results_reject_unsafe_xml_and_nonzero_signals(self):
        passing = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="TestResults" errors="0" tests="1" failures="0" skipped="0" time="0.001">
    <testcase classname="S" name="holdStartsImmediately()" time="0.001" />
  </testsuite>
</testsuites>
"""
        clean_log = "✔ Test holdStartsImmediately() passed after 0.001 seconds.\n"
        count, suites, functions = c.swift_structured_results(passing, 0, clean_log)
        self.assertEqual((count, suites, functions), (1, 1, ["holdStartsImmediately"]))
        rejected = {
            "empty": ("", 0, ""),
            "truncated": ("<testsuites><testsuite>", 0, ""),
            "doctype": ('<!DOCTYPE testsuites [<!ENTITY x "holdStartsImmediately">]>'
                        '<testsuites><testsuite name="T" tests="1" failures="0" errors="0" skipped="0">'
                        '<testcase name="&x;()" classname="S" time="0.001"/></testsuite></testsuites>', 0, ""),
            "entity": (passing.replace(
                "<testcase",
                "<!ENTITY x \"a\"><testcase",
            ), 0, ""),
            "duplicate pass and fail": (passing.replace(
                "</testsuite>",
                '<testcase classname="S" name="holdStartsImmediately()" time="0.001"><failure message="no">x</failure></testcase></testsuite>',
            ), 0, ""),
            "nonzero exit": (passing, 1, clean_log),
            "failure diagnostic": (passing, 0, clean_log + "✘ Test bad() failed\n"),
            "nonzero failures": (passing.replace('failures="0"', 'failures="1"'), 0, clean_log),
            "nonzero errors": (passing.replace('errors="0"', 'errors="2"'), 0, clean_log),
            "nonzero skipped": (passing.replace('skipped="0"', 'skipped="1"'), 0, clean_log),
            "non-integer failures": (passing.replace('failures="0"', 'failures="no"'), 0, clean_log),
            "oversized": (passing + "<!--" + ("x" * (32 * 1024 * 1024)) + "-->", 0, clean_log),
        }
        for name, (text, code, log) in rejected.items():
            with self.subTest(name):
                with self.assertRaises(c.Invalid):
                    c.swift_structured_results(text, code, log)

    def test_xunit_counts_root_totals_and_bounded_read_fail_closed(self):
        one = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="TestResults" errors="0" tests="1" failures="0" skipped="0" time="0.001">
    <testcase classname="S" name="holdStartsImmediately()" time="0.001" />
  </testsuite>
</testsuites>
"""
        torn = (Path(__file__).resolve().parent / "fixtures" / "portable-pointing-44344835181.log").read_text()
        clean = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="TestResults" errors="0" tests="2" failures="0" skipped="0" time="0.001">
    <testcase classname="PointingKeyGestureTests" name="holdStartsImmediately()" time="0.001" />
    <testcase classname="PointingOverlayGeometryTests" name="oneXDisplayWithANegativeOrigin()" time="0.001" />
  </testsuite>
</testsuites>
"""
        _, _, functions = c.swift_structured_results(clean, 0, torn)
        self.assertEqual(functions, ["holdStartsImmediately", "oneXDisplayWithANegativeOrigin"])
        with self.subTest("truncated"):
            with self.assertRaises(c.Invalid):
                c.swift_structured_results("<testsuites><testsuite>", 0)
        with self.subTest("empty suite"):
            empty = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="TestResults" errors="0" tests="0" failures="0" skipped="0" time="0"></testsuite>
</testsuites>
"""
            with self.assertRaises(c.Invalid):
                c.swift_structured_results(empty, 0)
        with self.subTest("tests count mismatch"):
            with self.assertRaises(c.Invalid):
                c.swift_structured_results(one.replace('tests="1"', 'tests="2"'), 0)
        with self.subTest("root failures"):
            with self.assertRaises(c.Invalid):
                c.swift_structured_results(one.replace("<testsuites>", '<testsuites failures="1">'), 0)
        with self.subTest("root malformed"):
            with self.assertRaises(c.Invalid):
                c.swift_structured_results(one.replace("<testsuites>", '<testsuites errors="no">'), 0)
        with self.subTest("nested mismatch"):
            nested = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Outer" errors="0" tests="5" failures="0" skipped="0">
    <testsuite name="Inner" errors="0" tests="1" failures="0" skipped="0">
      <testcase classname="S" name="holdStartsImmediately()" time="0.001" />
    </testsuite>
  </testsuite>
</testsuites>
"""
            with self.assertRaises(c.Invalid):
                c.swift_structured_results(nested, 0)
        with self.subTest("bom"):
            _, _, bom_functions = c.swift_structured_results("\ufeff" + one, 0)
            self.assertEqual(bom_functions, ["holdStartsImmediately"])
        with self.subTest("nested direct counts"):
            nested_ok = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Outer" errors="0" tests="0" failures="0" skipped="0">
    <testsuite name="Inner" errors="0" tests="1" failures="0" skipped="0">
      <testcase classname="S" name="holdStartsImmediately()" time="0.001" />
    </testsuite>
  </testsuite>
</testsuites>
"""
            _, _, nested_functions = c.swift_structured_results(nested_ok, 0)
            self.assertEqual(nested_functions, ["holdStartsImmediately"])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "results-swift-testing.xml"
            path.write_bytes("x".encode() * 9)
            with self.subTest("bounded read"):
                with self.assertRaises(c.Invalid):
                    c.read_swift_testing_xunit(path, limit=8)
            path.write_bytes("\xff\xfe<\x00".encode("latin1") if False else b"\xff\xfe<\x00")
            with self.subTest("utf-16"):
                with self.assertRaises(c.Invalid):
                    c.read_swift_testing_xunit(path, limit=32)

    def test_xunit_testcase_must_sit_in_a_suite_and_paths_stay_closed(self):
        one = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="TestResults" errors="0" tests="1" failures="0" skipped="0" time="0.001">
    <testcase classname="S" name="holdStartsImmediately()" time="0.001" />
  </testsuite>
</testsuites>
"""
        stray = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testcase classname="S" name="outside()" time="0.001" />
  <testsuite name="TestResults" errors="0" tests="1" failures="0" skipped="0" time="0.001">
    <testcase classname="S" name="holdStartsImmediately()" time="0.001" />
  </testsuite>
</testsuites>
"""
        wrapped = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="TestResults" errors="0" tests="0" failures="0" skipped="0" time="0.001">
    <wrapper>
      <testcase classname="S" name="holdStartsImmediately()" time="0.001" />
    </wrapper>
  </testsuite>
</testsuites>
"""
        with self.subTest("testcase directly under testsuites"):
            with self.assertRaises(c.Invalid):
                c.swift_structured_results(stray, 0)
        with self.subTest("testcase outside a testsuite"):
            with self.assertRaises(c.Invalid):
                c.swift_structured_results(wrapped, 0)
        with self.subTest("missing tests"):
            with self.assertRaises(c.Invalid):
                c.swift_structured_results(one.replace(' tests="1"', ""), 0)
        with self.subTest("tests not an integer"):
            with self.assertRaises(c.Invalid):
                c.swift_structured_results(one.replace('tests="1"', 'tests="no"'), 0)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "results-swift-testing.xml"
            target.write_text(one)
            link = root / "linked.xml"
            link.symlink_to(target)
            with self.subTest("symlink"):
                with self.assertRaises(c.Invalid):
                    c.read_swift_testing_xunit(link)
            folder = root / "not-a-file"
            folder.mkdir()
            with self.subTest("not a regular file"):
                with self.assertRaises(c.Invalid):
                    c.read_swift_testing_xunit(folder)

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

    def test_scribe_group_gets_the_linux_geometry_import_for_its_card_file(self):
        portable = runner.portable_module()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            linux = portable.prepare(output / "linux", "scribe", platform_name="linux")
            self.assertTrue((linux / "Sources/CoreGraphics/FoundationGeometry.swift").is_file())
            self.assertIn("CoreGraphics", c.load(linux / "validation-manifest.json")["compatibility"])
            darwin = portable.prepare(output / "darwin", "scribe", platform_name="darwin")
            self.assertFalse((darwin / "Sources/CoreGraphics").exists())

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

    def test_output_root_alias_does_not_make_receipt_an_input(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / "actual"
            root.mkdir()
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "Sources").mkdir()
            (root / "Sources/fixture.swift").write_text("let value = 1\n")
            (root / "output").mkdir()
            alias = base / "alias"
            alias.symlink_to(root, target_is_directory=True)
            before = c.source_snapshot(alias, alias / "output")
            (root / "output/result.json").write_text("{}")
            self.assertEqual(c.source_snapshot(alias, alias / "output"), before)
            self.assertEqual(c.source_snapshot(root, root / "output"), before)

    def test_portable_package_uses_the_production_macos_floor(self):
        portable = runner.portable_module()
        production = (c.ROOT / "Package.swift").read_text()
        self.assertIn('platforms: [.macOS("14.2")]', production)
        with tempfile.TemporaryDirectory() as directory:
            package = portable.prepare(Path(directory), "polyglot", platform_name="darwin")
            self.assertIn('platforms: [.macOS("14.2")]', (package / "Package.swift").read_text())

    def test_mac_geometry_excerpts_preserve_their_required_framework_import(self):
        portable = runner.portable_module()
        for group, original in [("presentation", "Mac/AXSnapshot.swift"),
                                ("recordly-geometry", "Present/CompanionMotion.swift")]:
            with self.subTest(group=group), tempfile.TemporaryDirectory() as directory:
                self.assertIn("import CoreGraphics", (c.ROOT / "Sources/ZeusCore" / original).read_text())
                package = portable.prepare(Path(directory), group, platform_name="darwin")
                self.assertTrue((package / "Sources/ZeusCore/PortableExcerpts.swift").read_text().startswith("import Foundation\nimport CoreGraphics\n"))
                self.assertEqual(c.load(package / "validation-manifest.json")["excerpt_imports"], ["Foundation", "CoreGraphics"])

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


def swift_log(names, summary_count=None, lost=()):
    """A Swift Testing console log: one outcome line per test, minus the lines the runner dropped."""
    lines = [f"◇ Test {name}() started.\n" for name in names]
    lines += [f"✔ Test {name}() passed after 0.1 seconds.\n" for name in names if name not in lost]
    count = len(names) if summary_count is None else summary_count
    return "".join(lines) + f"✔ Test run with {count} tests in 1 suite passed after 0.1 seconds.\n"


class DroppedLogLineTests(unittest.TestCase):
    """swift test can drop console lines under machine load; a log that lost any is not evidence."""

    def test_log_with_every_outcome_line_is_complete(self):
        self.assertTrue(c.swift_log_complete(swift_log(["one", "two", "three"])))

    def test_log_missing_an_outcome_line_is_incomplete(self):
        self.assertFalse(c.swift_log_complete(swift_log(["one", "two", "three"], lost=("two",))))

    def test_skipped_and_display_named_tests_and_case_lines_still_count_once(self):
        log = ("◇ Test one() started.\n✔ Test one() passed after 0.1 seconds.\n"
               "➜ Test skippedOne() skipped.\n"
               '✔ Test "A display name" passed after 0.1 seconds.\n'
               "◇ Test many(_:) started.\n"
               '✔ Test case passing 1 argument x → "a" to many(_:) passed after 0.1 seconds.\n'
               '✔ Test case passing 1 argument x → "b" to many(_:) passed after 0.1 seconds.\n'
               "✔ Test many(_:) passed after 0.1 seconds with 2 test cases.\n"
               "✔ Test run with 4 tests in 1 suite passed after 0.1 seconds.\n")
        self.assertTrue(c.swift_log_complete(log))
        self.assertFalse(c.swift_log_complete(log.replace("4 tests", "5 tests")))

    def test_a_line_cut_by_another_write_does_not_count(self):
        log = swift_log(["one", "two"]).replace(
            "✔ Test two() passed after 0.1 seconds.\n", "✔ Test two✔ Suite Cut passed after 0.1 seconds.\n")
        self.assertFalse(c.swift_log_complete(log))

    def test_log_without_one_summary_is_incomplete(self):
        self.assertFalse(c.swift_log_complete(""))
        self.assertFalse(c.swift_log_complete(swift_log(["one"]) * 2))


class PortableRetryTests(unittest.TestCase):
    ATTEMPT_LIMIT = 3

    def run_portable(self, logs):
        """Run one portable check whose successive attempts write the given logs; return row and call count."""
        calls = []
        def execute(command, log, timeout, environment=None):
            text = logs[min(len(calls), len(logs) - 1)]
            log.write_text(text)
            # swift test also writes structured results beside the console log; they keep every case the log lost.
            names = re.findall(r"◇ Test (\w+)\(\) started", text)
            cases = "".join(f'<testcase classname="S" name="{name}()" time="0.1"/>' for name in names)
            c.swift_testing_xunit_path(log.parent / "results.xml").write_text(
                '<?xml version="1.0" encoding="UTF-8"?><testsuites><testsuite name="TestResults" errors="0" '
                f'tests="{len(names)}" failures="0" skipped="0" time="0.1">{cases}</testsuite></testsuites>')
            calls.append(command)
            return 0, 0.1
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            def prepare(folder, group, **keywords):
                package = Path(folder) / "package"
                package.mkdir(exist_ok=True)
                (package / "validation-manifest.json").write_text("{}")
                return package
            portable = SimpleNamespace(prepare=prepare)
            definition = {"id": "portable-synthetic", "kind": "portable", "scope": "Synthetic.", "group": "synthetic"}
            with patch.object(runner, "execute", side_effect=execute), patch.object(runner, "manifest_matches"), \
                 patch.object(runner, "portable_module", return_value=portable), patch("builtins.print"):
                row = runner.run_check(definition, SimpleNamespace(mode="development", jobs=1, timeout=5), output, portable)
            kept = sorted(path.name for path in (output / "portable-synthetic").glob("test*.log"))
        return row, len(calls), kept

    def test_a_dropped_line_is_retried_and_the_complete_log_is_the_evidence(self):
        lossy = swift_log(["one", "two"], lost=("two",))
        row, calls, kept = self.run_portable([lossy, swift_log(["one", "two"])])
        self.assertEqual((row["status"], calls, row["passed_functions"]), ("passed", 2, ["one", "two"]))
        self.assertEqual(kept, ["test.attempt-1.log", "test.log"])

    def test_a_complete_log_runs_once(self):
        row, calls, kept = self.run_portable([swift_log(["one", "two"])])
        self.assertEqual((row["status"], calls, kept), ("passed", 1, ["test.log"]))

    def test_a_log_that_stays_incomplete_stops_at_the_attempt_limit(self):
        lossy = swift_log(["one", "two"], lost=("two",))
        row, calls, _ = self.run_portable([lossy])
        self.assertEqual(calls, self.ATTEMPT_LIMIT)
        # The structured results (PR #7) are the evidence: they keep the case the console log kept dropping.
        self.assertEqual(row["passed_functions"], ["one", "two"])

    def test_a_failing_run_is_never_retried(self):
        failed = "✘ Test one() recorded an issue: expected value\n✘ Test run with 1 test in 1 suite failed after 0.1 seconds.\n"
        calls = []
        def execute(command, log, timeout, environment=None):
            log.write_text(failed)
            calls.append(command)
            return 1, 0.1
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            def prepare(folder, group, **keywords):
                package = Path(folder) / "package"
                package.mkdir(exist_ok=True)
                return package
            portable = SimpleNamespace(prepare=prepare)
            definition = {"id": "portable-synthetic", "kind": "portable", "scope": "Synthetic.", "group": "synthetic"}
            with patch.object(runner, "execute", side_effect=execute), patch("builtins.print"):
                row = runner.run_check(definition, SimpleNamespace(mode="development", jobs=1, timeout=5), output, portable)
        self.assertEqual((row["status"], len(calls)), ("failed", 1))


class NativeBuildBarrierTests(unittest.TestCase):
    def definitions(self):
        return [{"id": "native-" + name, "kind": "native-fixture", "tier": "native-integration",
                 "scope": "Synthetic runner control-flow fixture only.", "suite": name,
                 "file": "Tests/ZeusAppTests/" + name + ".swift"} for name in ["FirstTests", "SecondTests", "ThirdTests"]]

    def run_matrix(self, output, build_code=0, failed_suite=None):
        commands = []
        def execute(command, log, timeout, environment=None):
            commands.append(command)
            if command[1] == "build":
                log.write_text("error: synthetic compiler failure\n" if build_code else "Build complete! (0.1s)\n")
                return build_code, 0.1
            if failed_suite and any(failed_suite in argument for argument in command):
                log.write_text("✘ Test syntheticCase() recorded an issue: expected value\n")
                return 1, 0.1
            log.write_text("✔ Test syntheticCase() passed after 0.1 seconds.\n✔ Test run with 1 test in 1 suite passed after 0.1 seconds.\n")
            if "--event-stream-output-path" in command:
                Path(command[command.index("--event-stream-output-path") + 1]).write_text("{}\n")
            return 0, 0.1
        result = {"checks": [], "source_snapshot_sha256": "a" * 64}
        with patch.object(runner.platform, "system", return_value="Darwin"), \
             patch.object(runner, "snapshot", return_value={"sha256": "a" * 64}), \
             patch.object(runner, "execute", side_effect=execute), patch("builtins.print"), \
             patch.object(runner, "discover_native", return_value={"status": "passed"}), \
             patch.object(runner.native, "validate_discovery_receipt", return_value={}), \
             patch.object(runner.native, "execution", return_value={"tests": 1, "suites": 1, "parameter_cases": 0,
                          "passed_cases": [{"file": "synthetic", "function": "syntheticCase"}]}):
            runner.run_checks(self.definitions(), SimpleNamespace(mode="full", jobs=2, timeout=10), output, None, result)
        return result, commands

    def test_failed_common_build_blocks_every_native_suite_without_executing_tests(self):
        with tempfile.TemporaryDirectory() as directory:
            result, commands = self.run_matrix(Path(directory), build_code=1)
            self.assertEqual(commands, [["swift", "build", "--build-tests", "--jobs", "2"]])
            self.assertEqual(result["native_build"]["status"], "failed")
            self.assertEqual(len(result["checks"]), 3)
            for check in result["checks"]:
                self.assertEqual((check["status"], check["blocker"], check["command"], check["tests"], check["artifacts"]),
                                 ("blocked", "native-build", [], 0, []))
            self.assertTrue((Path(directory) / "native-build/build.log").read_text().startswith("error:"))

    def test_one_runtime_failure_keeps_its_failure_and_runs_remaining_suites(self):
        with tempfile.TemporaryDirectory() as directory:
            result, commands = self.run_matrix(Path(directory), failed_suite="SecondTests")
            self.assertEqual(len(commands), 4)
            self.assertEqual(result["native_build"]["status"], "passed")
            self.assertEqual([c["status"] for c in result["checks"]], ["passed", "failed", "passed"])
            self.assertEqual(["--skip-build" in command for command in commands], [False, True, True, True])
            self.assertNotIn("blocker", result["checks"][1])

    def test_native_artifacts_allow_an_aliased_output_root_but_reject_redirected_children(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory).resolve()
            actual, alias = parent / "actual", parent / "alias"
            actual.mkdir()
            alias.symlink_to(actual, target_is_directory=True)
            result, _ = self.run_matrix(alias)
            self.assertEqual([row["status"] for row in result["checks"]], ["passed"] * 3)
            self.assertTrue(all(row["artifacts"] for row in result["checks"]))
            (actual / "redirected").symlink_to(actual / "native-FirstTests", target_is_directory=True)
            with self.assertRaises(c.Invalid):
                runner.artifact(alias / "redirected/test.log", alias)
            (actual / "linked.log").symlink_to(actual / "native-FirstTests/test.log")
            with self.assertRaises(c.Invalid):
                runner.artifact(alias / "linked.log", alias)

    def test_changed_source_after_compilation_cannot_execute_skip_build(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result, _ = self.run_matrix(output)
            with patch.object(runner.platform, "system", return_value="Darwin"), \
                 patch.object(runner, "snapshot", return_value={"sha256": "b" * 64}), \
                 patch.object(runner, "execute") as execute:
                row = runner.run_check({**self.definitions()[0], "id": "native-Changed"},
                                       SimpleNamespace(mode="full", jobs=2, timeout=10), output, None, result["native_build"])
            execute.assert_not_called()
            self.assertEqual((row["status"], row["blocker"], row["command"]), ("blocked", "native-build", []))

    def test_development_or_linux_never_attempts_a_native_build(self):
        for mode, host in [("development", "Darwin"), ("full", "Linux")]:
            with self.subTest(mode=mode, host=host), tempfile.TemporaryDirectory() as directory:
                result = {"checks": [], "source_snapshot_sha256": "a" * 64}
                with patch.object(runner.platform, "system", return_value=host), patch.object(runner, "execute") as execute:
                    runner.run_checks(self.definitions(), SimpleNamespace(mode=mode, jobs=2, timeout=10), Path(directory), None, result)
                execute.assert_not_called()
                self.assertNotIn("native_build", result)
                self.assertEqual({r["status"] for r in result["checks"]}, {"not-run" if mode == "development" else "blocked"})


class DeclaredTestCacheTests(unittest.TestCase):
    """The gate asks which tests a file declares once per case, so the answer is kept per file version."""

    def write(self, path, names):
        path.write_text("".join(f"    @Test func {name}() {{}}\n" for name in names))

    def test_second_ask_for_the_same_file_does_not_read_it_again(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "SampleTests.swift"
            self.write(path, ["first", "second"])
            self.assertEqual(c.declared_tests(path), ("first", "second"))
            with patch.object(Path, "read_text", side_effect=AssertionError("read again")):
                self.assertEqual(c.declared_tests(path), ("first", "second"))

    def test_a_changed_file_is_read_and_scanned_again(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "SampleTests.swift"
            self.write(path, ["first"])
            self.assertEqual(c.declared_tests(path), ("first",))
            self.write(path, ["first", "added"])
            self.assertEqual(c.declared_tests(path), ("first", "added"))

    def test_python_files_list_their_test_methods(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test_sample.py"
            path.write_text("class T:\n    def test_one(self): pass\n    def helper(self): pass\n")
            self.assertEqual(c.declared_tests(path), ("test_one",))


class ApprovalQueueGuardTests(unittest.TestCase):
    def test_a_spoken_yes_names_the_card_and_the_calendar_reader_does_not_ask(self):
        voice = (c.ROOT / "Sources/Zeus/App/VoiceTurnController.swift").read_text()
        self.assertIn("activateApproval(kind: .voice, cardID:", voice)
        reader = (c.ROOT / "Sources/Zeus/Calendar/LocalCalendarReader.swift").read_text()
        self.assertNotIn("requestFullAccessToEvents", reader)
        controller = (c.ROOT / "Sources/Zeus/Notch/NotchController.swift").read_text()
        self.assertIn("postApprovalAnnouncement(line)", controller)
        self.assertIn("NSAccessibility.post", controller)


if __name__ == "__main__":
    unittest.main(verbosity=2)
