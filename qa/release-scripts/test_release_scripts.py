"""Exercise release/install failure paths with fake macOS tools and throwaway bundles.

No real signing, notarization, installation, capture, or user defaults are touched.
Run: python3 qa/release-scripts/test_release_scripts.py
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
MOCK = r'''
import json, os, pathlib, shutil, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["ZEUS_TEST_LOG"], "a") as log:
    log.write(json.dumps([name] + args) + "\n")
if name == "codesign" and "--display" in args:
    state = os.environ.get("SIGNATURE_STATE", "valid")
    print("Authority=" + ("Developer ID Application: Test" if state != "adhoc" else "Zeus Local Dev"))
    print("TeamIdentifier=TEST123456")
    print("CodeDirectory v=20500 size=1 flags=" + ("0x10000(runtime)" if state != "no-runtime" else "0x0(none)"))
    if state != "no-timestamp": print("Timestamp=Nov 9, 2026")
elif name == "ditto":
    if os.environ.get("FAIL_BACKUP") == "1" and "Rollbacks" in args[-1]: sys.exit(1)
    if "-c" in args: pathlib.Path(args[-1]).write_text("zip")
    else: shutil.copytree(args[-2], args[-1], dirs_exist_ok=True, copy_function=shutil.copy2)
elif name == "hdiutil":
    if os.environ.get("FAIL_IMAGE") == "1": sys.exit(1)
    pathlib.Path(args[-1]).write_text("new-dmg")
elif name == "xcrun" and args[:2] == ["notarytool", "submit"]:
    print(json.dumps({"status": os.environ.get("NOTARY_STATUS", "Accepted")}))
elif name == "plutil":
    print(json.loads(pathlib.Path(args[-1]).read_text())["status"])
elif name == "pgrep": sys.exit(0 if os.environ.get("APP_RUNNING") == "1" else 1)
elif name == "mv":
    if os.environ.get("FAIL_INSTALL") == "1" and ".zeus-install." in args[-2] and args[-2].endswith("/Zeus.app"):
        sys.exit(1)
    os.execv("/bin/mv", ["mv"] + args)
elif name == "rm":
    # test.sh also removes preference stubs; never touch the real user's home in this harness.
    root = pathlib.Path(os.environ["ZEUS_TEST_ROOT"]).resolve()
    if all(pathlib.Path(a).resolve().is_relative_to(root) for a in args if not a.startswith("-")):
        os.execv("/bin/rm", ["rm"] + args)
elif name == "defaults":
    if args == ["domains"]:
        print("app.zeus.mac, zeus.tests.example.12345678-ABCD-1234-ABCD-123456789ABC, zeus.tests.onboarding.Skip")
elif name == "xcode-select": print("/missing-test-toolchain")
elif name == "swift" and "--show-bin-path" in args: print(os.environ["ZEUS_TEST_BIN"])
'''


class ReleaseScripts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="zeus-release-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        (self.root / "build").mkdir()
        (self.root / "Resources").mkdir()
        for name in ("bundle.sh", "package.sh", "verify-release-signature.sh", "install.sh", "test.sh"):
            shutil.copy2(REPO / "scripts" / name, self.root / "scripts" / name)
        self.log = self.root / "commands.jsonl"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for command in ("codesign", "ditto", "hdiutil", "xcrun", "spctl", "plutil", "pgrep", "mv", "rm", "defaults", "xcode-select", "swift", "npm", "plistbuddy"):
            path = self.bin / command
            path.write_text(f"#!{sys.executable}\n" + MOCK)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", ZEUS_TEST_LOG=str(self.log), ZEUS_TEST_ROOT=str(self.root))
        self.env.pop("RELEASE", None)
        self.env.pop("SIGN_IDENTITY", None)
        self.env.pop("NOTARY_PROFILE", None)
        (self.root / "Resources/AppIcon.icns").write_text("icon")

    def run_script(self, name, *args, **env):
        return subprocess.run(["bash", str(self.root / "scripts" / name), *map(str, args)], cwd=self.root,
                              env=dict(self.env, **env), text=True, capture_output=True)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def app(self, path, text):
        binary = path / "Contents/MacOS/Zeus"
        binary.parent.mkdir(parents=True)
        binary.write_text(text)
        binary.chmod(0o755)
        return path

    def package_fixture(self):
        self.app(self.root / "build/Zeus.app", "new-app")
        (self.root / "build/ZEUS.dmg").write_text("previous-good-dmg")
        (self.root / "scripts/bundle.sh").write_text("#!/usr/bin/env bash\nexit 0\n")

    def install_fixture(self):
        source = self.app(self.root / "build/Zeus.app", "new-app")
        target = self.app(self.root / "Applications/Zeus.app", "previous-app")
        self.env["ZEUS_ROLLBACK_DIR"] = str(self.root / "Rollbacks")
        return source, target

    def bundle_fixture(self):
        # Only substitute the macOS-only absolute PlistBuddy path; all shell control flow is original.
        bundle = self.root / "scripts/bundle.sh"
        bundle.write_text(bundle.read_text().replace("/usr/libexec/PlistBuddy", "plistbuddy"))
        for name in ("Info.plist", "Logo.png", "Logo.pdf", "MenuBarTemplate.png", "MenuBarTemplate@2x.png", "NOTICES.txt", "Zeus.entitlements"):
            (self.root / "Resources" / name).write_text("fixture")
        for name in ("dist", "icons", "node_modules"):
            (self.root / "extension" / name).mkdir(parents=True)
        for name in ("manifest.json", "popup.html"):
            (self.root / "extension" / name).write_text("fixture")
        output = self.root / "swift-output"
        output.mkdir()
        for name in ("Zeus", "zeus-hook", "zeus-bridge", "zeus-cli"):
            (output / name).write_text("executable")
        self.env["ZEUS_TEST_BIN"] = str(output)

    def test_developer_id_bundle_uses_secure_timestamps(self):
        self.bundle_fixture()
        result = self.run_script("bundle.sh", RELEASE="1", SIGN_IDENTITY="Developer ID Application: Test")
        self.assertEqual(result.returncode, 0, result.stderr)
        signatures = [c for c in self.commands() if c[:2] == ["codesign", "--force"]]
        self.assertEqual(len(signatures), 4)
        self.assertTrue(all("--timestamp" in c and "--timestamp=none" not in c for c in signatures))

    def test_ad_hoc_bundle_remains_available_for_local_validation(self):
        self.bundle_fixture()
        result = self.run_script("bundle.sh", SIGN_IDENTITY="-")
        self.assertEqual(result.returncode, 0, result.stderr)
        signatures = [c for c in self.commands() if c[:2] == ["codesign", "--force"]]
        self.assertEqual(len(signatures), 4)
        self.assertTrue(all("--timestamp=none" in c for c in signatures))

    def test_release_requires_identity_and_profile_before_build(self):
        self.package_fixture()
        result = self.run_script("package.sh", RELEASE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / "build/ZEUS.dmg").read_text(), "previous-good-dmg")
        self.assertEqual(self.commands(), [])

    def test_failed_image_keeps_previous_dmg(self):
        self.package_fixture()
        result = self.run_script("package.sh", FAIL_IMAGE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / "build/ZEUS.dmg").read_text(), "previous-good-dmg")
        self.assertEqual(list((self.root / "build").glob(".zeus-package.*")), [])

    def test_rejected_notarization_never_staples_or_publishes(self):
        self.package_fixture()
        result = self.run_script("package.sh", RELEASE="1", SIGN_IDENTITY="Developer ID Application: Test",
                                 NOTARY_PROFILE="test", NOTARY_STATUS="Invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / "build/ZEUS.dmg").read_text(), "previous-good-dmg")
        self.assertFalse(any(c[:2] == ["xcrun", "stapler"] for c in self.commands()))

    def test_release_assesses_app_and_dmg_before_publication(self):
        self.package_fixture()
        result = self.run_script("package.sh", RELEASE="1", SIGN_IDENTITY="Developer ID Application: Test", NOTARY_PROFILE="test")
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        assessments = [i for i, c in enumerate(commands) if c[0] == "spctl"]
        publication = next(i for i, c in enumerate(commands) if c[0] == "mv" and c[-1] == "build/ZEUS.dmg")
        self.assertEqual(len(assessments), 2)
        self.assertTrue(all(i < publication for i in assessments))
        self.assertEqual((self.root / "build/ZEUS.dmg").read_text(), "new-dmg")
        self.assertTrue((self.root / "build/ZEUS.dmg.sha256").exists())

    def test_preview_is_explicitly_not_a_release(self):
        self.package_fixture()
        result = self.run_script("package.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("not been notarized", result.stdout)
        self.assertFalse(any(c[0] == "spctl" for c in self.commands()))

    def test_signature_checks_fail_closed(self):
        app = self.app(self.root / "build/Zeus.app", "new-app")
        for state in ("adhoc", "no-runtime", "no-timestamp"):
            with self.subTest(state=state):
                self.assertNotEqual(self.run_script("verify-release-signature.sh", app, SIGNATURE_STATE=state).returncode, 0)
        self.assertEqual(self.run_script("verify-release-signature.sh", app).returncode, 0)

    def test_installer_keeps_verified_rollback(self):
        source, target = self.install_fixture()
        result = self.run_script("install.sh", source, target)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((target / "Contents/MacOS/Zeus").read_text(), "new-app")
        backups = list((self.root / "Rollbacks").glob("*/Zeus.app/Contents/MacOS/Zeus"))
        self.assertEqual([p.read_text() for p in backups], ["previous-app"])

    def test_failed_install_restores_previous_copy(self):
        source, target = self.install_fixture()
        result = self.run_script("install.sh", source, target, FAIL_INSTALL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((target / "Contents/MacOS/Zeus").read_text(), "previous-app")
        self.assertEqual(len(list((self.root / "Rollbacks").glob("*/Zeus.app"))), 1)

    def test_failed_backup_does_not_replace_installed_copy(self):
        source, target = self.install_fixture()
        result = self.run_script("install.sh", source, target, FAIL_BACKUP="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((target / "Contents/MacOS/Zeus").read_text(), "previous-app")

    def test_running_app_is_not_replaced(self):
        source, target = self.install_fixture()
        result = self.run_script("install.sh", source, target, APP_RUNNING="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((target / "Contents/MacOS/Zeus").read_text(), "previous-app")
        self.assertFalse((self.root / "Rollbacks").exists())

    def test_test_defaults_cleanup_reaches_matching_domains_only(self):
        result = self.run_script("test.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        deletes = [c[2] for c in self.commands() if c[:2] == ["defaults", "delete"]]
        self.assertEqual(deletes, ["zeus.tests.example.12345678-ABCD-1234-ABCD-123456789ABC", "zeus.tests.onboarding.Skip"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
