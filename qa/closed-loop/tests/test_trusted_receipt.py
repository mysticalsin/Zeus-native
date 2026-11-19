"""Full mode consumes a trusted-Mac receipt only after strict re-validation; development never does."""
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import trusted_ax

SPEC = importlib.util.spec_from_file_location("zeus_runner_for_trusted_receipt", HERE / "run.py")
run = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(run)
SPEC = importlib.util.spec_from_file_location("zeus_gate_for_trusted_receipt", HERE / "gate.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)

SHA = "a" * 40
IDENT = "device-ScribeTrustedAccessibilityJourneyTests"
TEST = "ZeusAppTests." + trusted_ax.SUITE + "/" + trusted_ax.REQUIRED_FUNCTION + "()/ScribeComponentJourneyTests.swift:1:1"


class TrustedReceiptTests(unittest.TestCase):
    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="zeus-trusted-receipt-"))
        self.addCleanup(shutil.rmtree, self.base, True)
        self.source = self.base / "run-source"
        self.source.mkdir()
        self.output = self.base / "output"
        self.output.mkdir()
        pass_mark = {"messages": [{"symbol": "pass"}]}
        rows = [{"kind": "test", "payload": {"kind": "function", "id": TEST}},
                {"kind": "event", "payload": {"kind": "runStarted"}},
                {"kind": "event", "payload": {"kind": "testStarted", "testID": TEST}},
                {"kind": "event", "payload": {"kind": "testEnded", "testID": TEST, **pass_mark}},
                {"kind": "event", "payload": {"kind": "runEnded", **pass_mark}}]
        (self.source / "events.jsonl").write_text("".join(json.dumps({"version": 0, **row}) + "\n" for row in rows))
        self.receipt = self.source / "receipt.json"
        self.write({})

    def write(self, change):
        value = {"schema_version": 1, "result": "passed", "sha": SHA, "dirty": False, "timestamp": "20261110T000000Z",
                 "exit_code": 0, "filter": trusted_ax.FILTER, "test_ids": [TEST], "problems": [],
                 "events": str(self.source / "events.jsonl"), "log": str(self.source / "test.log"), **change}
        self.receipt.write_text(json.dumps(value))

    def consume(self, mode="full", receipt="default"):
        args = SimpleNamespace(mode=mode, trusted_receipt=self.receipt if receipt == "default" else receipt)
        definition = {"id": IDENT, "kind": "trusted-native-fixture", "scope": "x"}
        with patch.object(run, "git", return_value=SHA):
            return run.run_check(definition, args, self.output, None)

    def test_valid_receipt_passes_in_full_mode_with_artifacts_and_positive_count(self):
        row = self.consume()
        self.assertEqual(row["status"], "passed", row)
        self.assertEqual((row["tests"], row["exit_code"], row["passed_functions"]), (1, 0, [trusted_ax.REQUIRED_FUNCTION]))
        self.assertEqual([a["path"] for a in row["artifacts"]], [f"{IDENT}/receipt.json", f"{IDENT}/events.jsonl"])
        self.assertNotIn("reason", row)

    def test_full_mode_without_a_receipt_stays_blocked_with_the_reason(self):
        row = self.consume(receipt=None)
        self.assertEqual(row["status"], "blocked")
        self.assertIn("Trusted Mac evidence is required", row["reason"])
        self.assertEqual((row["tests"], row["artifacts"]), (0, []))

    def test_development_mode_ignores_even_a_valid_receipt(self):
        row = self.consume("development")
        self.assertEqual((row["status"], row["tests"], row["artifacts"], row["command"], row["exit_code"]),
                         ("not-run", 0, [], [], None))

    def assert_rejected(self, text):
        row = self.consume()
        self.assertEqual(row["status"], "blocked", row)
        self.assertIn("trusted Mac receipt rejected", row["reason"])
        self.assertIn(text, row["reason"])
        self.assertEqual((row["tests"], row["artifacts"]), (0, []))

    def test_each_defect_is_rejected(self):
        cases = {"wrong sha": ({"sha": "b" * 40}, "another source sha"),
                 "dirty tree": ({"dirty": True}, "dirty tree"),
                 "failed result": ({"result": "failed"}, "result is not passed"),
                 "bad exit": ({"exit_code": 1}, "exit_code"),
                 "problems": ({"problems": ["x"]}, "problems"),
                 "schema": ({"schema_version": 2}, "schema_version"),
                 "missing required test": ({"test_ids": []}, "required test")}
        for name, (change, text) in cases.items():
            with self.subTest(name):
                self.output = self.base / ("output-" + name.replace(" ", "-"))
                self.output.mkdir()
                self.write(change)
                self.assert_rejected(text)

    def test_missing_event_file_is_rejected(self):
        (self.source / "events.jsonl").unlink()
        self.assert_rejected("events file is missing")

    def test_event_stream_that_no_longer_validates_is_rejected(self):
        (self.source / "events.jsonl").write_text("")
        self.assert_rejected("events do not validate")

    def test_symlinked_events_are_rejected(self):
        real = self.base / "real-events.jsonl"
        (self.source / "events.jsonl").rename(real)
        (self.source / "events.jsonl").symlink_to(real)
        self.assert_rejected("events file is missing or redirected")

    def test_symlinked_receipt_is_rejected(self):
        real = self.base / "real-receipt.json"
        self.receipt.rename(real)
        self.receipt.symlink_to(real)
        self.assert_rejected("missing, redirected or oversized")

    def valid_output(self):
        row = self.consume()
        self.assertEqual(row["status"], "passed", row)
        return row

    def test_gate_revalidates_a_valid_row_itself(self):
        row = self.valid_output()
        self.assertEqual(gate.validate_trusted_row(row, IDENT, self.output, SHA), 1)

    def test_gate_rejects_rows_that_claim_more_than_their_receipt(self):
        row = self.valid_output()
        for name, expected, change in (
                ("wrong sha", "b" * 40, {}),
                ("inflated count", SHA, {"tests": 5}),
                ("no artifacts", SHA, {"artifacts": []}),
                ("blocked", SHA, {"status": "blocked", "reason": "no receipt"})):
            with self.subTest(name), self.assertRaises(ValueError):
                gate.validate_trusted_row({**row, **change}, IDENT, self.output, expected)

    def test_gate_rejects_a_receipt_edited_after_the_run_and_a_dirty_one(self):
        row = self.valid_output()
        copied = self.output / IDENT / "receipt.json"
        value = json.loads(copied.read_text())
        value["dirty"] = True
        copied.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            gate.validate_trusted_row(row, IDENT, self.output, SHA)
        row["artifacts"][0]["sha256"] = gate.digest(copied)
        with self.assertRaisesRegex(ValueError, "dirty tree"):
            gate.validate_trusted_row(row, IDENT, self.output, SHA)

    def test_gate_rejects_symlinked_evidence(self):
        row = self.valid_output()
        events = self.output / IDENT / "events.jsonl"
        real = self.base / "moved.jsonl"
        events.rename(real)
        events.symlink_to(real)
        with self.assertRaises(ValueError):
            gate.validate_trusted_row(row, IDENT, self.output, SHA)

    def test_full_gate_without_trusted_evidence_still_names_the_requirement(self):
        with self.assertRaisesRegex(ValueError, "trusted Mac evidence is required"):
            gate.validate_trusted_row({"status": "not-run"}, IDENT, self.output, SHA)


if __name__ == "__main__":
    unittest.main()
