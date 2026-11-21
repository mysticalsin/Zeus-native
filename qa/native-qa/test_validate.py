"""Fail-closed checks for the native hands-on QA receipt.

A pass needs every public step, a real screenshot, and result "passed".
Missing, skipped, and failed steps are not a pass. No app is launched.
"""
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qa" / "closed-loop"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import human_qa  # noqa: E402

HEAD = "2722dcb7497d5415fbc1fcb1f65c49629966a281"
PRODUCTION = [
    "qa/native-qa/validate.py",
    "qa/native-qa/harness.py",
    "qa/native-qa/steps.json",
    "scripts/qa-native-run.sh",
    "scripts/qa-native-validate.sh",
]
FORBIDDEN = (
    "pkill",
    "killall",
    "install.sh",
    "ci_motion_profile",
    "GITHUB_ACTIONS=",
    "keychain",
    "Keychain",
)
COMMERCIAL = ("Zoom", "Slack", "Chrome", "Discord", "Firefox", "WhatsApp", "Spotify", "Microsoft Teams")


def load():
    import validate
    return validate


def png(folder, name="shot.png"):
    path = Path(folder) / name
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + b"x" * 32)
    return path


class Catalog(unittest.TestCase):
    def test_catalog_is_the_public_hands_on_step_list(self):
        v = load()
        self.assertEqual([step["id"] for step in v.catalog()], human_qa.expected_ids())

    def test_each_step_has_a_script_and_no_commercial_app_name(self):
        v = load()
        blob = (ROOT / "qa" / "native-qa" / "steps.json").read_text()
        for name in COMMERCIAL:
            self.assertNotIn(name, blob)
        self.assertNotIn("\u2014", blob)
        for step in v.catalog():
            self.assertTrue(step["title"].strip())
            self.assertIsInstance(step["script"], list)
            self.assertGreaterEqual(len(step["script"]), 2)
            for line in step["script"]:
                self.assertTrue(line.strip())
                self.assertNotIn("\u2014", line)
        by_id = {step["id"]: "\n".join(step["script"]) for step in v.catalog()}
        self.assertIn("consent", by_id["scribe.start-mic"].lower())
        self.assertIn("microphone", by_id["scribe.start-mic"].lower())
        self.assertIn("cancel", by_id["record.countdown"].lower())
        self.assertIn("capture", by_id["record.countdown"].lower())


class ReceiptSlots(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.v = load()
        self.fills = 0

    def filled(self, **overrides):
        app = self.dir / "Zeus-latest-2722dcb7.app"
        receipt = self.v.blank_receipt(HEAD, str(app))
        self.fills += 1
        shots = self.dir / f"shots-{self.fills}"
        shots.mkdir()
        for index, step in enumerate(receipt["steps"]):
            shot = png(shots, f"{index}.png")
            step["screenshot"] = str(shot)
            step["result"] = "passed"
        for sid, fields in overrides.items():
            for step in receipt["steps"]:
                if step["id"] == sid:
                    step.update(fields)
        return receipt

    def test_blank_receipt_has_an_empty_slot_per_step_and_is_not_a_pass(self):
        app = str(self.dir / "Zeus-latest-2722dcb7.app")
        receipt = self.v.blank_receipt(HEAD, app)
        self.assertEqual(receipt["schema"], "zeus-native-qa-receipt/1")
        self.assertEqual(receipt["verdict"], "not-run")
        self.assertEqual(receipt["head"], HEAD)
        self.assertEqual([step["id"] for step in receipt["steps"]], human_qa.expected_ids())
        for step in receipt["steps"]:
            self.assertEqual(step["screenshot"], "")
            self.assertEqual(step["result"], "")
            self.assertIn("script", step)
        verdict, reasons = self.v.judge(receipt, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(reasons)

    def test_every_passed_step_with_a_screenshot_is_a_pass(self):
        verdict, reasons = self.v.judge(self.filled(), self.dir)
        self.assertEqual(reasons, [])
        self.assertEqual(verdict, "pass")

    def test_a_missing_step_is_not_a_pass(self):
        receipt = self.filled()
        receipt["steps"] = [step for step in receipt["steps"] if step["id"] != "record.countdown"]
        verdict, reasons = self.v.judge(receipt, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("record.countdown" in reason for reason in reasons))

    def test_skipped_failed_and_not_run_are_not_a_pass(self):
        for result in ("skipped", "failed", "not-run", "PASS", "pass", ""):
            verdict, reasons = self.v.judge(self.filled(**{"talk.voice": {"result": result}}), self.dir)
            self.assertEqual(verdict, "fail", result)
            self.assertTrue(any("talk.voice" in reason for reason in reasons), result)

    def test_a_passed_step_without_a_real_screenshot_is_not_a_pass(self):
        missing = self.filled(**{"launch.window": {"screenshot": str(self.dir / "gone.png")}})
        empty = self.filled()
        for step in empty["steps"]:
            if step["id"] == "launch.window":
                path = Path(step["screenshot"])
                path.write_bytes(b"")
        link = self.filled()
        target = png(self.dir, "real.png")
        linked = self.dir / "link.png"
        linked.symlink_to(target)
        for step in link["steps"]:
            if step["id"] == "launch.window":
                step["screenshot"] = str(linked)
        blank = self.filled(**{"launch.window": {"screenshot": ""}})
        for receipt in (missing, empty, link, blank):
            verdict, reasons = self.v.judge(receipt, self.dir)
            self.assertEqual(verdict, "fail")
            self.assertTrue(any("launch.window" in reason for reason in reasons))

    def test_relative_screenshot_resolves_beside_the_receipt(self):
        receipt = self.filled()
        shot = png(self.dir, "beside.png")
        for step in receipt["steps"]:
            if step["id"] == "quit.clean":
                step["screenshot"] = "beside.png"
        verdict, reasons = self.v.judge(receipt, self.dir)
        self.assertEqual(reasons, [])
        self.assertEqual(verdict, "pass")
        self.assertTrue(shot.is_file())

    def test_duplicate_or_unknown_step_is_not_a_pass(self):
        duplicate = self.filled()
        duplicate["steps"].append(dict(duplicate["steps"][0]))
        verdict, reasons = self.v.judge(duplicate, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(reasons)
        unknown = self.filled()
        unknown["steps"][0]["id"] = "not.a.real.step"
        verdict, reasons = self.v.judge(unknown, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("not.a.real.step" in reason or "launch.process" in reason for reason in reasons))

    def test_a_claimed_pass_still_fails_when_a_step_failed(self):
        receipt = self.filled(**{"alerts.trigger": {"result": "failed"}})
        receipt["verdict"] = "pass"
        verdict, reasons = self.v.judge(receipt, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("alerts.trigger" in reason for reason in reasons))

    def test_credential_shaped_text_is_not_a_pass(self):
        receipt = self.filled()
        receipt["steps"][0]["note"] = "sk-" + ("a" * 20)
        verdict, reasons = self.v.judge(receipt, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("credential" in reason.lower() for reason in reasons))

    def test_installed_app_path_and_wrong_build_name_are_not_a_pass(self):
        installed = self.filled()
        installed["app"] = "/Applications/Zeus.app"
        verdict, reasons = self.v.judge(installed, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("/Applications/Zeus.app" in reason for reason in reasons))
        wrong = self.filled()
        wrong["app"] = str(self.dir / "Zeus.app")
        verdict, reasons = self.v.judge(wrong, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("Zeus-latest-2722dcb7.app" in reason for reason in reasons))

    def test_head_must_be_the_full_lowercase_sha(self):
        receipt = self.filled()
        receipt["head"] = HEAD.upper()
        verdict, _reasons = self.v.judge(receipt, self.dir)
        self.assertEqual(verdict, "fail")
        receipt["head"] = HEAD[:12]
        receipt["app"] = str(self.dir / "Zeus-latest-2722dcb7.app")
        verdict, _reasons = self.v.judge(receipt, self.dir)
        self.assertEqual(verdict, "fail")


class HarnessGuards(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / "home"
        self.repo = Path(self.tmp.name) / "repo"
        (self.home / "Desktop").mkdir(parents=True)
        self.repo.mkdir()
        self.v = load()
        self.calls = []

    def usage(self, free):
        def inner(_path):
            return type("U", (), {"free": free})()
        return inner

    def test_desktop_build_name_uses_the_sha_prefix(self):
        dest = self.v.desktop_app(self.home, HEAD)
        self.assertEqual(dest, self.home / "Desktop" / "Zeus-latest-2722dcb7.app")
        with self.assertRaises(self.v.Refused):
            self.v.desktop_app(self.home, "not-a-sha")

    def test_installed_app_destination_is_refused(self):
        with self.assertRaises(self.v.Refused) as caught:
            self.v.refuse_if_installed(Path("/Applications/Zeus.app"))
        self.assertIn("/Applications/Zeus.app", str(caught.exception))

    def test_build_commands_stay_inside_the_harness_rules(self):
        commands = self.v.build_commands()
        self.assertEqual(commands, [["swift", "build", "-c", "release"]])
        blob = " ".join(" ".join(cmd) for cmd in commands)
        for word in ("install.sh", "pkill", "killall", "security", "ci_motion_profile"):
            self.assertNotIn(word, blob)

    def test_low_disk_refuses_before_any_build(self):
        with self.assertRaises(self.v.Refused) as caught:
            self.v.prepare(HEAD, self.home, self.repo, self.usage(self.v.MIN_FREE_BYTES - 1), self.calls.append)
        self.assertIn("6 GiB", str(caught.exception))
        self.assertEqual(self.calls, [])

    def test_exact_six_gib_allows_the_swift_build(self):
        receipt = self.v.prepare(HEAD, self.home, self.repo, self.usage(self.v.MIN_FREE_BYTES), self.calls.append)
        self.assertEqual(self.calls, [["swift", "build", "-c", "release"]])
        self.assertEqual(receipt["verdict"], "not-run")
        self.assertEqual(Path(receipt["app"]).name, "Zeus-latest-2722dcb7.app")
        self.assertTrue(all(step["result"] == "" and step["screenshot"] == "" for step in receipt["steps"]))

    def test_non_mac_refuses_before_disk_or_build(self):
        def usage(_path):
            raise AssertionError("disk must not be checked off macOS")
        with self.assertRaises(self.v.Refused) as caught:
            self.v.prepare(
                HEAD, self.home, self.repo, usage, self.calls.append, platform_name="Linux"
            )
        self.assertIn("macOS", str(caught.exception))
        self.assertEqual(self.calls, [])

    def test_missing_desktop_refuses_before_a_build(self):
        shutil.rmtree(self.home / "Desktop")
        with self.assertRaises(self.v.Refused):
            self.v.prepare(HEAD, self.home, self.repo, self.usage(self.v.MIN_FREE_BYTES), self.calls.append)
        self.assertEqual(self.calls, [])


class SourceRules(unittest.TestCase):
    def test_production_files_exist_and_avoid_forbidden_actions(self):
        v = load()
        self.assertEqual(v.MIN_FREE_BYTES, 6 * 1024 ** 3)
        for rel in PRODUCTION:
            path = ROOT / rel
            self.assertTrue(path.is_file(), rel)
            text = path.read_text()
            self.assertNotIn("\u2014", text, rel)
            for word in FORBIDDEN:
                self.assertNotIn(word, text, f"{rel} contains {word}")
            for name in COMMERCIAL:
                self.assertNotIn(name, text, rel)
        run = (ROOT / "scripts" / "qa-native-run.sh").read_text()
        validate = (ROOT / "scripts" / "qa-native-validate.sh").read_text()
        self.assertIn("qa/native-qa/harness.py", run)
        self.assertIn("qa/native-qa/validate.py", validate)
        self.assertNotIn("bundle.sh", run)
        self.assertNotIn("package.sh", run)
        harness = (ROOT / "qa" / "native-qa" / "harness.py").read_text()
        self.assertIn("refuse_if_installed", harness)
        self.assertIn("/Applications/Zeus.app", harness)
        self.assertNotIn("shell=True", harness)


if __name__ == "__main__":
    unittest.main()
