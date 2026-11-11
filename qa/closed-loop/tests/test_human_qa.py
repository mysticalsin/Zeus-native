"""Selftests for the human QA report/receipt writer and evidence folder logic. No app is launched."""
import datetime
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import human_qa as h  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]


def step(sid, status="PASS", reason="", latency=10, wait=20, journey=None, ended=None):
    return {"id": sid, "journey": journey or sid.split(".")[0], "name": sid, "status": status, "reason": reason,
            "latency_ms": latency, "max_wait_ms": wait, "started_at": 1.0, "ended_at": ended or 1.0, "evidence": []}


def all_steps(**overrides):
    out = []
    for ids in h.JOURNEYS.values():
        for sid in ids:
            out.append(step(sid, **overrides.get(sid, {})))
    return out


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def write_results(self, steps):
        main = [s for s in steps if s["journey"] != "persist"]
        persist = [s for s in steps if s["journey"] == "persist"]
        (self.dir / "results-main.json").write_text(json.dumps({"steps": main}))
        if persist:
            (self.dir / "results-persist.json").write_text(json.dumps({"steps": persist}))


class EvidenceFolder(Base):
    def test_new_dir_is_timestamped_private_and_never_reused(self):
        now = datetime.datetime(2026, 11, 11, 10, 0, 0)
        a = h.new_evidence_dir(self.dir / "base", now)
        b = h.new_evidence_dir(self.dir / "base", now)
        self.assertEqual(a.name, "20261111-100000")
        self.assertEqual(b.name, "20261111-100000-2")
        self.assertEqual(a.stat().st_mode & 0o777, 0o700)

    def test_app_inside_repo_is_refused(self):
        app = ROOT / "fake.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        try:
            (app / "Contents/MacOS/Zeus").write_text("")
            (app / "Contents/Info.plist").write_text("")
            with self.assertRaises(h.Refused):
                h.check_app(app)
        finally:
            import shutil
            shutil.rmtree(app)

    def test_app_outside_repo_must_be_a_real_bundle(self):
        with self.assertRaises(h.Refused):
            h.check_app(self.dir / "missing.app")
        folder = self.dir / "Zeus.app"
        folder.mkdir()
        with self.assertRaises(h.Refused):
            h.check_app(folder)  # no executable
        (folder / "Contents/MacOS").mkdir(parents=True)
        (folder / "Contents/MacOS/Zeus").write_text("")
        (folder / "Contents/Info.plist").write_text("")
        self.assertEqual(h.check_app(folder), folder.resolve())
        (self.dir / "notes.txt").write_text("x")
        with self.assertRaises(h.Refused):
            h.check_app(self.dir / "notes.txt")

    def test_crash_reports_only_zeus_and_only_since_start(self):
        reports = self.dir / "reports"
        reports.mkdir()
        old = reports / "Zeus-old.ips"
        old.write_text("x")
        os.utime(old, (100, 100))
        new = reports / "Zeus-new.ips"
        new.write_text("x")
        (reports / "Other-new.ips").write_text("x")
        (reports / "Zeus-new.txt").write_text("x")
        self.assertEqual(h.crash_reports_since(time.time() - 60, reports), [new])
        self.assertEqual(h.crash_reports_since(0, self.dir / "none"), [])


class StepValidation(unittest.TestCase):
    def test_fail_and_manual_need_a_reason(self):
        self.assertEqual(h.validate_step(step("a.b")), [])
        self.assertTrue(h.validate_step(step("a.b", "FAIL")))
        self.assertTrue(h.validate_step(step("a.b", "MANUAL")))
        self.assertEqual(h.validate_step(step("a.b", "FAIL", "slow")), [])

    def test_bad_status_and_latency_rejected(self):
        self.assertTrue(h.validate_step(step("a.b", "OK")))
        self.assertTrue(h.validate_step(step("a.b", latency=-1)))
        self.assertTrue(h.validate_step(step("a.b", latency=True)))


class Finalize(Base):
    def run_finalize(self, steps, rc=0, only=None, crashes=()):
        self.write_results(steps)
        return h.finalize(self.dir, "/Apps/Zeus.app", time.time(), rc, only, crashes)

    def test_all_pass_is_pass_and_writes_report_and_receipt(self):
        self.assertEqual(self.run_finalize(all_steps()), "pass")
        report = (self.dir / "report.md").read_text()
        self.assertIn("Verdict: **pass**", report)
        receipt = json.loads((self.dir / "receipt.json").read_text())
        self.assertEqual(receipt["verdict"], "pass")
        self.assertEqual(receipt["counts"]["FAIL"], 0)
        self.assertIn("report.md", receipt["files"])
        self.assertEqual(len(receipt["steps"]), sum(len(v) for v in h.JOURNEYS.values()))

    def test_manual_does_not_fail_but_is_listed(self):
        steps = all_steps(**{"talk.voice": {"status": "MANUAL", "reason": "needs a human"}})
        self.assertEqual(self.run_finalize(steps), "pass-with-manual")
        self.assertIn("## Needs a human", (self.dir / "report.md").read_text())

    def test_a_failure_fails_the_run_and_shows_a_log_excerpt(self):
        (self.dir / "zeus-log.txt").write_text("2026-11-11 10:00:01.000 Zeus[1] boom happened\n2026-11-11 11:00:00.000 later\n")
        when = datetime.datetime(2026, 11, 11, 10, 0, 2).timestamp()
        steps = all_steps(**{"settings.page.voice": {"status": "FAIL", "reason": "rendered after 4000 ms", "ended": when}})
        self.assertEqual(self.run_finalize(steps, rc=1), "fail")
        report = (self.dir / "report.md").read_text()
        self.assertIn("boom happened", report)
        self.assertNotIn("later", report)

    def test_missing_steps_fail_the_run(self):
        steps = [s for s in all_steps() if s["id"] != "record.countdown"]
        self.assertEqual(self.run_finalize(steps), "fail")
        self.assertIn("record.countdown", (self.dir / "report.md").read_text())

    def test_crash_report_or_driver_error_fails_the_run(self):
        self.assertEqual(self.run_finalize(all_steps(), crashes=["/x/Zeus-1.ips"]), "fail")
        self.assertEqual(self.run_finalize(all_steps(), rc=3), "fail")
        self.assertEqual(self.run_finalize(all_steps(), rc=2), "fail")

    def test_only_one_journey_needs_only_its_steps(self):
        steps = [s for s in all_steps() if s["journey"] == "alerts"]
        steps = [dict(s, status="MANUAL", reason="r") if s["id"] == "alerts.trigger" else s for s in steps]
        self.assertEqual(self.run_finalize(steps, only="alerts"), "pass-with-manual")

    def test_freeze_over_two_seconds_is_reported(self):
        steps = all_steps(**{"scribe.open": {"wait": 2600}})
        self.run_finalize(steps)
        self.assertIn("Waits over 2 s", (self.dir / "report.md").read_text())
        self.assertEqual(json.loads((self.dir / "receipt.json").read_text())["freeze_steps"], ["scribe.open"])

    def test_receipt_refuses_credentials(self):
        steps = all_steps(**{"talk.voice": {"status": "MANUAL", "reason": "sk-abcdefghijklmnopqrstuvwx"}})
        with self.assertRaises(h.Refused):
            self.run_finalize(steps)

    def test_malformed_results_file_is_a_problem_not_a_pass(self):
        (self.dir / "results-main.json").write_text("{nope")
        self.assertEqual(h.finalize(self.dir, "/Apps/Zeus.app", time.time(), 0), "fail")


class DriverAgreement(unittest.TestCase):
    """The Swift driver must contain every step id this writer expects (and no id it does not know)."""

    def test_every_expected_step_id_appears_in_the_driver(self):
        source = (ROOT / "scripts/human-qa.swift").read_text()
        for sid in h.expected_ids():
            if sid.startswith("settings.page."):
                continue  # built from the page list: "settings.page.\(page.raw)"
            self.assertIn(f'"{sid}"', source, sid)
        self.assertIn('"settings.page.\\(page.raw)"', source)
        for raw in h.SETTINGS_PAGES:
            self.assertIn(f'("{raw}",', source, raw)

    def test_driver_has_no_macros(self):
        source = (ROOT / "scripts/human-qa.swift").read_text()
        code = "\n".join(l for l in source.splitlines() if not l.lstrip().startswith("//"))
        for banned in ("@Observable", "#Preview", "import Testing", "@Test", "#expect"):
            self.assertNotIn(banned, code)

    def test_driver_never_starts_capture_or_mic_by_default(self):
        source = (ROOT / "scripts/human-qa.swift").read_text()
        self.assertIn("opts.allowMic", source)
        self.assertIn("pressEscape()", source)

    def test_script_guards(self):
        script = (ROOT / "scripts/human-qa.sh").read_text()
        for needle in ("log stream", "swiftc", "--check-trust", "y/N", "refusing", "crashes", "finalize"):
            self.assertIn(needle, script, needle)
        self.assertIn("DiagnosticReports", (ROOT / "qa/closed-loop/human_qa.py").read_text())
        driver = (ROOT / "scripts/human-qa.swift").read_text()
        self.assertIn("/usr/bin/sample", driver)
        self.assertIn("AXIsProcessTrusted", driver)
        self.assertNotIn("swift build", re.sub(r"#.*", "", script))
        self.assertNotIn("disable-sandbox", script)


if __name__ == "__main__":
    unittest.main()
