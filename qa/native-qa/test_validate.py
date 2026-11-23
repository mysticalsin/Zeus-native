"""Fail-closed checks for the native hands-on QA receipt.

A pass needs every public step, a real PNG screenshot, and result PASS.
MANUAL, FAIL, and a stand-in image are not a pass. The harness does not open Zeus.
"""
import io
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from contextlib import redirect_stdout

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


def write_png(path, width, height, paint):
    """Minimal 8-bit RGB PNG. paint(x, y) returns three bytes."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(paint(x, y))

    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    blob = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b"")
    Path(path).write_bytes(blob)
    return Path(path)


def png(folder, name="shot.png"):
    """A 200x100 screenshot with two colours. One colour must not pass."""
    return write_png(
        Path(folder) / name, 200, 100,
        lambda x, _y: b"\x00\x00\x00" if x < 100 else b"\xff\x00\x00",
    )


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
        self.app = self.dir / "Zeus-latest-2722dcb7.app"
        macos = self.app / "Contents" / "MacOS"
        macos.mkdir(parents=True)
        (macos / "Zeus").write_text("binary\n")

    def filled(self, **overrides):
        app = self.app
        receipt = self.v.blank_receipt(HEAD, str(app))
        receipt["manual_run"] = True
        receipt["opened_by_harness"] = False
        receipt["runtime_app_pid"] = 4242
        receipt["runtime_app_bundle"] = str(app)
        receipt["log"] = "swift build finished\n"
        self.fills += 1
        shots = self.dir / f"shots-{self.fills}"
        shots.mkdir()
        for index, step in enumerate(receipt["steps"]):
            shot = png(shots, f"{index}.png")
            step["screenshot"] = str(shot)
            step["result"] = "PASS"
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

    def test_manual_fail_and_legacy_passed_are_not_a_pass(self):
        self.assertEqual(human_qa.STATUSES, ("PASS", "FAIL", "MANUAL"))
        for result in ("passed", "MANUAL", "FAIL", "skipped", "failed", "not-run", "pass", ""):
            verdict, reasons = self.v.judge(self.filled(**{"talk.voice": {"result": result}}), self.dir)
            self.assertEqual(verdict, "fail", result)
            self.assertTrue(any("talk.voice" in reason for reason in reasons), result)

    def test_one_byte_file_is_not_a_png_screenshot(self):
        receipt = self.filled()
        for step in receipt["steps"]:
            if step["id"] == "launch.window":
                Path(step["screenshot"]).write_bytes(b"x")
        verdict, reasons = self.v.judge(receipt, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("launch.window" in reason and "PNG" in reason for reason in reasons))

    def test_small_or_one_colour_png_is_not_a_screenshot(self):
        cases = (
            (199, 100, lambda x, _y: b"\x00\x00\x00" if x < 50 else b"\xff\x00\x00", "200x100"),
            (200, 99, lambda x, _y: b"\x00\x00\x00" if x < 50 else b"\xff\x00\x00", "200x100"),
            (200, 100, lambda _x, _y: b"\x0a\x14\x1e", "colour"),
        )
        for width, height, paint, needle in cases:
            receipt = self.filled()
            for step in receipt["steps"]:
                if step["id"] == "launch.window":
                    write_png(step["screenshot"], width, height, paint)
            verdict, reasons = self.v.judge(receipt, self.dir)
            self.assertEqual(verdict, "fail", (width, height, needle))
            self.assertTrue(any("launch.window" in reason and needle in reason for reason in reasons), reasons)

    def test_runtime_pid_or_bundle_is_required(self):
        missing = self.filled()
        missing["runtime_app_pid"] = None
        missing["runtime_app_bundle"] = None
        verdict, reasons = self.v.judge(missing, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("runtime" in reason.lower() for reason in reasons))
        pid_only = self.filled()
        pid_only["runtime_app_bundle"] = None
        pid_only["runtime_app_pid"] = 5151
        verdict, reasons = self.v.judge(pid_only, self.dir)
        self.assertEqual(reasons, [])
        self.assertEqual(verdict, "pass")
        bundle_only = self.filled()
        bundle_only["runtime_app_pid"] = None
        verdict, reasons = self.v.judge(bundle_only, self.dir)
        self.assertEqual(reasons, [])
        self.assertEqual(verdict, "pass")

    def test_steps_out_of_order_are_not_a_pass(self):
        receipt = self.filled()
        receipt["steps"][0], receipt["steps"][1] = receipt["steps"][1], receipt["steps"][0]
        verdict, reasons = self.v.judge(receipt, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("order" in reason for reason in reasons), reasons)

    def test_empty_or_truncated_log_is_not_a_pass(self):
        for log in ("", "   ", "\n", None):
            receipt = self.filled()
            if log is None:
                receipt.pop("log", None)
            else:
                receipt["log"] = log
            verdict, reasons = self.v.judge(receipt, self.dir)
            self.assertEqual(verdict, "fail", repr(log))
            self.assertTrue(any("empty" in reason.lower() and "log" in reason.lower() for reason in reasons), reasons)
        receipt = self.filled()
        receipt["log"] = "swift build started"
        verdict, reasons = self.v.judge(receipt, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("truncat" in reason.lower() and "log" in reason.lower() for reason in reasons), reasons)

    def test_an_unproven_receipt_is_not_a_pass(self):
        receipt = self.filled()
        receipt["verdict"] = "unproven"
        receipt["platform"] = "Linux"
        receipt["journeys"] = [{"id": "launch", "status": "unproven", "reason": "macOS only"}]
        verdict, reasons = self.v.judge(receipt, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any(reason == "receipt is unproven" for reason in reasons), reasons)
        self.assertTrue(any(reason == "launch: unproven" for reason in reasons), reasons)
        step_only = self.filled(**{"launch.process": {"result": "unproven"}})
        verdict, reasons = self.v.judge(step_only, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("launch.process" in reason and "unproven" in reason for reason in reasons), reasons)
        hosted = self.filled()
        hosted["platform"] = "Linux"
        verdict, reasons = self.v.judge(hosted, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("Linux" in reason and "unproven" in reason for reason in reasons), reasons)

    def test_opening_zeus_or_a_fail_mark_is_not_a_pass(self):
        opened = self.filled()
        opened["opened_by_harness"] = True
        verdict, reasons = self.v.judge(opened, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any("open" in reason.lower() for reason in reasons))
        marked = self.filled()
        marked["verdict"] = "FAIL"
        verdict, reasons = self.v.judge(marked, self.dir)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any(reason.startswith("receipt is marked FAIL") for reason in reasons))

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
        seen = []

        def run(command, cwd=None):
            seen.append((list(command), None if cwd is None else Path(cwd)))

        receipt = self.v.prepare(HEAD, self.home, self.repo, self.usage(self.v.MIN_FREE_BYTES), run)
        self.assertEqual(seen, [(["swift", "build", "-c", "release"], self.repo)])
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

    def test_harness_build_uses_the_repo_cwd(self):
        import harness
        calls = []
        original = harness.subprocess.run

        def fake(command, cwd=None, check=False, **kwargs):
            calls.append((list(command), None if cwd is None else Path(cwd), check))
            return type("R", (), {"returncode": 0})()

        harness.subprocess.run = fake
        try:
            harness._run(["swift", "build", "-c", "release"], cwd=self.repo)
        finally:
            harness.subprocess.run = original
        self.assertEqual(calls, [(["swift", "build", "-c", "release"], self.repo, True)])

    def test_missing_desktop_refuses_before_a_build(self):
        shutil.rmtree(self.home / "Desktop")
        with self.assertRaises(self.v.Refused):
            self.v.prepare(HEAD, self.home, self.repo, self.usage(self.v.MIN_FREE_BYTES), self.calls.append)
        self.assertEqual(self.calls, [])

    def test_linux_labels_every_journey_unproven_and_does_not_build(self):
        import harness
        calls = []

        def usage(_path):
            raise AssertionError("disk must not be checked off macOS")

        out, code = harness.execute(
            self.repo, self.home, HEAD, "Linux", usage=usage, run=lambda *_args, **_kwargs: calls.append(_args)
        )
        self.assertEqual(calls, [])
        self.assertNotEqual(code, 0)
        self.assertEqual(list(self.home.rglob("*.app")), [])
        body = json.loads(Path(out).read_text())
        self.assertEqual(body["verdict"], "unproven")
        self.assertEqual(body["platform"], "Linux")
        self.assertEqual([journey["id"] for journey in body["journeys"]], list(human_qa.JOURNEYS))
        for journey in body["journeys"]:
            self.assertEqual(journey["status"], "unproven")
            self.assertEqual(journey["reason"], "macOS only")
        self.assertEqual([step["result"] for step in body["steps"]], ["unproven"] * len(body["steps"]))
        self.assertEqual([step["id"] for step in body["steps"]], human_qa.expected_ids())
        verdict, reasons = self.v.judge(body, self.home)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any(reason == "receipt is unproven" for reason in reasons), reasons)
        self.assertTrue(all(f"{name}: unproven" in reasons for name in human_qa.JOURNEYS), reasons)

    def test_main_on_linux_records_unproven_journeys(self):
        import harness
        original = harness.platform.system
        harness.platform.system = lambda: "Linux"
        buffer = io.StringIO()
        try:
            with redirect_stdout(buffer):
                code = harness.main(["--repo", str(self.repo), "--home", str(self.home), "--head", HEAD])
        finally:
            harness.platform.system = original
        self.assertEqual(code, 2)
        text = buffer.getvalue()
        self.assertIn("unproven", text)
        receipt = self.home / "Desktop" / "Zeus-latest-2722dcb7.qa-receipt.json"
        body = json.loads(receipt.read_text())
        self.assertEqual(body["verdict"], "unproven")
        self.assertFalse((self.home / "Desktop" / "Zeus-latest-2722dcb7.app").exists())

    def test_ci_on_mac_refuses_before_a_build(self):
        import harness
        import os
        previous = os.environ.get("CI")
        os.environ["CI"] = "true"
        original = harness.subprocess.run

        def forbidden(*_args, **_kwargs):
            self.fail("CI must not start swift build")

        harness.subprocess.run = forbidden
        try:
            with self.assertRaises(harness.Refused) as caught:
                harness.execute(
                    self.repo, self.home, HEAD, "Darwin",
                    usage=self.usage(self.v.MIN_FREE_BYTES),
                )
        finally:
            harness.subprocess.run = original
            if previous is None:
                os.environ.pop("CI", None)
            else:
                os.environ["CI"] = previous
        self.assertIn("CI", str(caught.exception))
        self.assertEqual(self.calls, [])

    def test_a_failed_build_writes_a_fail_receipt_with_a_log(self):
        import harness
        import os
        previous = os.environ.get("CI")
        os.environ["CI"] = "true"

        def run(command, cwd=None):
            raise subprocess.CalledProcessError(1, command, output="out", stderr="swift failed\n")

        try:
            out, code = harness.execute(
                self.repo, self.home, HEAD, "Darwin",
                usage=self.usage(self.v.MIN_FREE_BYTES), run=run,
                assemble=lambda *_args, **_kwargs: self.fail("assemble must not run"),
            )
        finally:
            if previous is None:
                os.environ.pop("CI", None)
            else:
                os.environ["CI"] = previous
        self.assertNotEqual(code, 0)
        self.assertEqual(list(self.home.rglob("*.app")), [])
        body = json.loads(Path(out).read_text())
        self.assertEqual(body["verdict"], "FAIL")
        self.assertEqual(body["platform"], "Darwin")
        self.assertIn("swift failed", body["log"])
        self.assertTrue(body["log"].endswith("\n"))
        verdict, reasons = self.v.judge(body, self.home)
        self.assertEqual(verdict, "fail")
        self.assertTrue(any(reason.startswith("receipt is marked FAIL") for reason in reasons))

    def test_a_finished_build_records_the_log_and_stays_fail(self):
        import harness
        import os
        previous = os.environ.get("CI")
        os.environ["CI"] = "true"

        def run(command, cwd=None):
            return subprocess.CompletedProcess(command, 0, stdout="built\n", stderr="")

        def assemble(_repo, dest):
            macos = Path(dest) / "Contents" / "MacOS"
            macos.mkdir(parents=True)
            (macos / "Zeus").write_text("binary\n")

        try:
            out, code = harness.execute(
                self.repo, self.home, HEAD, "Darwin",
                usage=self.usage(self.v.MIN_FREE_BYTES), run=run, assemble=assemble, processes=[],
            )
        finally:
            if previous is None:
                os.environ.pop("CI", None)
            else:
                os.environ["CI"] = previous
        self.assertNotEqual(code, 0)
        body = json.loads(Path(out).read_text())
        self.assertEqual(body["verdict"], "FAIL")
        self.assertIn("swift build -c release", body["log"])
        self.assertIn("built", body["log"])
        self.assertTrue(body["log"].endswith("\n"))
        self.assertTrue(all(step["result"] == "" for step in body["steps"]))
        verdict, _reasons = self.v.judge(body, self.home)
        self.assertEqual(verdict, "fail")


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
        self.assertIn("manual-run", harness)
        self.assertIn("unproven", harness)
        self.assertNotIn("shell=True", harness)
        self.assertNotIn("open -n", harness)
        self.assertNotIn("open -a", harness)


class ManualRun(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / "home"
        (self.home / "Desktop").mkdir(parents=True)
        self.v = load()
        import harness
        self.harness = harness

    def bundle(self):
        dest = self.home / "Desktop" / "Zeus-latest-2722dcb7.app"
        macos = dest / "Contents" / "MacOS"
        macos.mkdir(parents=True)
        (macos / "Zeus").write_text("binary\n")
        return dest

    def test_capture_never_accepts_the_installed_app(self):
        with self.assertRaises(self.harness.Refused):
            self.harness.capture_runtime(
                Path("/Applications/Zeus.app"),
                [{"pid": 9, "bundle": "/Applications/Zeus.app"}],
            )
        dest = self.bundle()
        found = self.harness.capture_runtime(dest, [{"pid": 9, "bundle": str(dest)}])
        self.assertEqual(found, {"pid": 9, "bundle": str(dest)})
        self.assertIsNone(self.harness.capture_runtime(dest, [{"pid": 9, "bundle": "/Applications/Zeus.app"}]))

    def test_failed_run_writes_fail_or_nothing(self):
        dest = self.bundle()
        receipt = self.v.blank_receipt(HEAD, str(dest))
        out, code = self.harness.record_manual_run(receipt, dest, None)
        self.assertNotEqual(code, 0)
        if out is None:
            self.assertEqual(list(dest.parent.glob("*.qa-receipt.json")), [])
            return
        written = json.loads(Path(out).read_text())
        self.assertEqual(written["verdict"], "FAIL")
        self.assertIs(written["manual_run"], True)
        self.assertIs(written["opened_by_harness"], False)
        verdict, _reasons = self.v.judge(written, dest.parent)
        self.assertEqual(verdict, "fail")
        captured = self.harness.record_manual_run(
            receipt, dest, {"pid": 77, "bundle": str(dest)}
        )
        out2, code2 = captured
        self.assertNotEqual(code2, 0)
        body = json.loads(Path(out2).read_text())
        self.assertEqual(body["verdict"], "FAIL")
        self.assertEqual(body["runtime_app_pid"], 77)
        self.assertEqual(body["runtime_app_bundle"], str(dest))
        verdict, _reasons = self.v.judge(body, dest.parent)
        self.assertEqual(verdict, "fail")


if __name__ == "__main__":
    unittest.main()
