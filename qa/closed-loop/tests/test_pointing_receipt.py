"""Selftests for the pointing receipt validator. No app is launched."""
import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pointing_receipt  # noqa: E402


def good_receipt():
    metrics = {
        "lifecycle": {"states": "idle>listening>processing>speaking>idle", "requests_after_spoil": 0, "input_begins_after_double_hold": 1},
        "capture": {"capture_attempts_in_turn": 1, "image_width": 2048, "image_height": 1280},
        "coordinates": {"max_error_pt": 0.0001, "per_display": [{"display_id": 1, "scale": 2, "origin": [0, 0]}]},
        "targeting": {"probes": [{"expected": "a", "found": "a"}, {"expected": "b", "found": "b"}]},
        "protocol": {"partial_events_rendered": 0, "split_cuts": 12, "malformed_op_rejected": True,
                     "off_image_marks_dropped": 1, "outside_point_returns_nil": True},
        "rendering": {"ring_center_error_pt": 1.2, "clicks_pass_through": True, "strokes_while_held": 1,
                      "fixture_clicks_while_held": 0, "overlay_level": 1000},
        "sync": {"flight_start_minus_first_audio_ms": 3.2},
        "interruption": {"esc_to_stopped_ms": 8, "second_hold_to_stopped_ms": 11, "next_turn_completed": True,
                         "microphone_idle": True},
        "repeat": {"turns": 3, "completed": 3, "windows_before": 4, "windows_after": 4},
        "resources": {"max_main_thread_gap_ms": 40},
    }
    checks = [{"id": key, "title": key, "required": key != "resources", "status": "passed", "reason": "", "metrics": value}
              for key, value in metrics.items()]
    return {"schema_version": 1, "timed_out": False, "mode": "deterministic", "provider_path": "scripted",
            "app": {"build_stamp": "20261110-1", "git_sha": "abc"}, "macos": "Version 27.2",
            "started_at": "2026-11-10T12:00:00Z", "finished_at": "2026-11-10T12:00:30Z",
            "displays": [{"id": 1, "scale": 2, "origin": [0, 0], "size": [1440, 900]}],
            "inputs": {"keys": "injected"}, "checks": checks}


def row(receipt, check_id):
    return next(r for r in receipt["checks"] if r["id"] == check_id)


class PointingReceiptValidatorTests(unittest.TestCase):
    def test_a_complete_receipt_is_valid_and_has_no_blocks(self):
        problems, blocked = pointing_receipt.validate(good_receipt(), rc=0)
        self.assertEqual((problems, blocked), ([], []))

    def test_the_cli_exit_code_is_zero_for_a_full_pass(self):
        path = Path(self.id() + ".json")
        try:
            path.write_text(json.dumps(good_receipt()))
            self.assertEqual(pointing_receipt.main(["x", str(path), "--rc", "0"]), 0)
        finally:
            path.unlink(missing_ok=True)

    def test_a_missing_check_is_rejected(self):
        receipt = good_receipt()
        receipt["checks"] = [r for r in receipt["checks"] if r["id"] != "sync"]
        problems, _ = pointing_receipt.validate(receipt)
        self.assertIn("sync: missing from the receipt", problems)

    def test_a_pass_with_no_metrics_is_a_fake_pass(self):
        receipt = good_receipt()
        row(receipt, "interruption")["metrics"] = {}
        problems, _ = pointing_receipt.validate(receipt, rc=0)
        self.assertTrue(any("interruption: passed with no metrics" in p for p in problems), problems)

    def test_a_pass_whose_numbers_do_not_prove_it_is_rejected(self):
        for check_id, key, value in [("interruption", "esc_to_stopped_ms", 400), ("coordinates", "max_error_pt", 3),
                                     ("rendering", "ring_center_error_pt", 9), ("sync", "flight_start_minus_first_audio_ms", -5),
                                     ("rendering", "overlay_level", 3)]:
            with self.subTest(check_id=check_id, key=key):
                receipt = good_receipt()
                row(receipt, check_id)["metrics"][key] = value
                problems, _ = pointing_receipt.validate(receipt)
                self.assertTrue(problems, "a pass contradicted by its own metrics must fail")

    def test_blocked_without_a_reason_or_pane_is_rejected(self):
        receipt = good_receipt()
        entry = row(receipt, "capture")
        entry.update({"status": "blocked", "reason": "", "metrics": {}})
        problems, _ = pointing_receipt.validate(receipt)
        self.assertTrue(any("capture: blocked without a reason" in p for p in problems))
        self.assertTrue(any("capture: blocked without a System Settings pane" in p for p in problems))

    def test_blocked_with_reason_and_pane_is_valid_but_not_a_full_pass(self):
        receipt = good_receipt()
        entry = row(receipt, "capture")
        entry.update({"status": "blocked", "reason": "Screen Recording is not granted", "permission_pane": "Privacy_ScreenCapture", "metrics": {}})
        problems, blocked = pointing_receipt.validate(receipt, rc=3)
        self.assertEqual(problems, [])
        self.assertEqual(blocked, ["capture"])
        path = Path(self.id() + ".json")
        try:
            path.write_text(json.dumps(receipt))
            self.assertEqual(pointing_receipt.main(["x", str(path), "--rc", "3"]), 3)
        finally:
            path.unlink(missing_ok=True)

    def test_rc_zero_with_blocked_checks_is_inconsistent(self):
        receipt = good_receipt()
        row(receipt, "targeting").update({"status": "blocked", "reason": "no Accessibility", "permission_pane": "Privacy_Accessibility", "metrics": {}})
        problems, _ = pointing_receipt.validate(receipt, rc=0)
        self.assertIn("the app exited 0 although checks are blocked", problems)

    def test_failed_checks_and_timeouts_are_rejected(self):
        receipt = good_receipt()
        row(receipt, "repeat").update({"status": "failed", "reason": "leaked a window"})
        receipt["timed_out"] = True
        problems, _ = pointing_receipt.validate(receipt)
        self.assertTrue(any("repeat: failed" in p for p in problems))
        self.assertTrue(any("timeout" in p for p in problems))

    def test_a_required_check_cannot_be_not_measured_but_resources_can(self):
        receipt = good_receipt()
        row(receipt, "resources").update({"status": "not-measured", "reason": "no sampler", "metrics": {}})
        self.assertEqual(pointing_receipt.validate(receipt)[0], [])
        row(receipt, "sync").update({"status": "not-measured", "reason": "x", "metrics": {}})
        self.assertTrue(any("sync: a required check cannot be not-measured" in p for p in pointing_receipt.validate(receipt)[0]))

    def test_secrets_and_captured_content_are_rejected(self):
        receipt = good_receipt()
        row(receipt, "capture")["metrics"]["screenshot"] = "x"
        row(receipt, "lifecycle")["reason"] = "Authorization: Bearer abcdefghijklmnop"
        receipt["header_note"] = "sk-" + "a" * 30
        problems, _ = pointing_receipt.validate(receipt)
        self.assertTrue(any("could carry captured content" in p for p in problems))
        self.assertTrue(any("credential" in p for p in problems))

    def test_unknown_duplicate_or_malformed_input_is_rejected(self):
        receipt = good_receipt()
        receipt["checks"].append(copy.deepcopy(receipt["checks"][0]))
        receipt["checks"].append({"id": "extra", "status": "passed", "metrics": {"a": 1}})
        problems, _ = pointing_receipt.validate(receipt)
        self.assertTrue(any("listed twice" in p for p in problems))
        self.assertTrue(any("extra: unknown check" in p for p in problems))
        self.assertEqual(pointing_receipt.validate([])[0], ["receipt is not a JSON object"])
        bad = good_receipt(); bad["schema_version"] = 2; bad["displays"] = []
        problems, _ = pointing_receipt.validate(bad)
        self.assertTrue(any("schema_version" in p for p in problems) and any("displays" in p for p in problems))


if __name__ == "__main__":
    unittest.main()
