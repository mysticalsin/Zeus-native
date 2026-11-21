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
import json, os, pathlib, re, shutil, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
logged = []
redact = False
for arg in args:
    if redact:
        logged.append("REDACTED")
        redact = False
    elif name == "security" and arg == "-p":
        logged.append(arg)
        redact = True
    else:
        logged.append(arg)
with open(os.environ["ZEUS_TEST_LOG"], "a") as log:
    log.write(json.dumps([name] + logged) + "\n")

def pinned(constant, fallback):
    script = pathlib.Path(os.environ["ZEUS_TEST_ROOT"]) / "scripts/verify-release-signature.sh"
    text = script.read_text() if script.exists() else ""
    match = re.search(r'^' + constant + r'="([^"]*)"', text, re.M)
    return match.group(1) if match else fallback

if name == "codesign" and "--display" in args:
    state = os.environ.get("SIGNATURE_STATE", "valid")
    special = {
        "wrong-team": "OTHERTEAM1",
        "empty-team": "",
        "short-team": "TEAMID123",
        "long-team": "TEAMID12345",
        "lower-team": "testteam01",
        "symbol-team": "TEST-TEAM1",
    }
    team = special[state] if state in special else pinned("EXPECTED_TEAM_ID", "TESTTEAM01")
    bundle = "com.example.notzeus" if state == "wrong-bundle" else pinned("EXPECTED_BUNDLE_ID", "app.zeus.mac")
    print("Identifier=" + bundle)
    print("Authority=" + ("Developer ID Application: Test" if state != "adhoc" else "Zeus Local Dev"))
    print("TeamIdentifier=" + team)
    print("CodeDirectory v=20500 size=1 flags=" + ("0x10000(runtime)" if state != "no-runtime" else "0x0(none)"))
    if state != "no-timestamp": print("Timestamp=Nov 9, 2026")
elif name == "security" and args[:2] == ["find-identity", "-p"] and "codesigning" in args:
    print('  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Zeus Local Dev"')
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
        for command in ("codesign", "ditto", "hdiutil", "xcrun", "spctl", "plutil", "pgrep", "mv", "rm", "defaults", "xcode-select", "swift", "npm", "plistbuddy", "security"):
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
        # The binaries are signed with a secure timestamp, then verify-release-signature.sh
        # refuses the release because EXPECTED_TEAM_ID is still the ZEUSTEAMID placeholder.
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("ZEUSTEAMID", result.stderr)
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

    def test_bundle_strips_symbols_from_app_and_helpers_before_signing(self):
        # Lean install: unstripped binaries were 62 MB of the 194 MB app (language data is not in the bundle at all).
        self.bundle_fixture()
        result = self.run_script("bundle.sh", SIGN_IDENTITY="-")
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        stripped = [c[-1] for c in commands if c[:3] == ["xcrun", "strip", "-S"] and "-x" in c]
        self.assertEqual(sorted(Path(p).name for p in stripped), ["Zeus", "zeus", "zeus-bridge", "zeus-hook"])
        first_sign = next(i for i, c in enumerate(commands) if c[:2] == ["codesign", "--force"])
        last_strip = max(i for i, c in enumerate(commands) if c[:3] == ["xcrun", "strip", "-S"])
        self.assertLess(last_strip, first_sign)

    def test_symbols_can_be_kept_for_a_profiling_build(self):
        self.bundle_fixture()
        result = self.run_script("bundle.sh", SIGN_IDENTITY="-", ZEUS_KEEP_SYMBOLS="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c for c in self.commands() if c[:2] == ["xcrun", "strip"]], [])

    def test_bundle_ships_product_resources_but_never_test_resource_bundles(self):
        # A local QA launch of the CI preview found Zeus_ZeusCoreTests.bundle (test fixtures) inside the app.
        self.bundle_fixture()
        output = Path(self.env["ZEUS_TEST_BIN"])
        for name in ("Zeus_Zeus.bundle", "Zeus_ZeusCoreTests.bundle", "Zeus_ZeusAppTests.bundle"):
            (output / name).mkdir()
            (output / name / "resource.txt").write_text("fixture")
        result = self.run_script("bundle.sh", SIGN_IDENTITY="-")
        self.assertEqual(result.returncode, 0, result.stderr)
        resources = self.root / "build/Zeus.app/Contents/Resources"
        self.assertTrue((resources / "Zeus_Zeus.bundle/resource.txt").is_file())
        self.assertEqual(sorted(p.name for p in resources.glob("*Tests.bundle")), [])

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

    def use_synthetic_team(self, team="TESTTEAM01"):
        # ZEUSTEAMID is a fail-closed placeholder. Acceptance tests replace it in the
        # throwaway copy only. They never treat the placeholder as a good team.
        path = self.root / "scripts/verify-release-signature.sh"
        text = path.read_text()
        needle = 'EXPECTED_TEAM_ID="ZEUSTEAMID"'
        self.assertIn(needle, text)
        path.write_text(text.replace(needle, f'EXPECTED_TEAM_ID="{team}"', 1))

    def now_playing(self, app):
        extra = app / "Contents/Resources/zeus-now-playing"
        extra.parent.mkdir(parents=True, exist_ok=True)
        extra.write_text("helper")
        extra.chmod(0o755)
        return extra

    def test_signature_checks_fail_closed(self):
        app = self.app(self.root / "build/Zeus.app", "new-app")
        self.now_playing(app)
        self.use_synthetic_team()
        for state in ("adhoc", "no-runtime", "no-timestamp"):
            with self.subTest(state=state):
                self.assertNotEqual(self.run_script("verify-release-signature.sh", app, SIGNATURE_STATE=state).returncode, 0)
        self.assertEqual(self.run_script("verify-release-signature.sh", app).returncode, 0)

    def test_missing_now_playing_helper_fails_closed(self):
        # The expected resource helper is absent. A sibling helper is present, so the
        # failure is the missing zeus-now-playing binary and not an empty Helpers directory.
        app = self.app(self.root / "build/Zeus.app", "new-app")
        helper = app / "Contents/Helpers/zeus-bridge"
        helper.parent.mkdir(parents=True)
        helper.write_text("bridge")
        helper.chmod(0o755)
        self.use_synthetic_team()
        self.assertFalse((app / "Contents/Resources/zeus-now-playing").exists())
        result = self.run_script("verify-release-signature.sh", app)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("zeus-now-playing", result.stderr)

    def test_placeholder_team_id_refuses_the_release(self):
        app = self.app(self.root / "build/Zeus.app", "new-app")
        self.now_playing(app)
        script = (self.root / "scripts/verify-release-signature.sh").read_text()
        self.assertIn('EXPECTED_TEAM_ID="ZEUSTEAMID"', script)
        result = self.run_script("verify-release-signature.sh", app)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("ZEUSTEAMID", result.stderr)

    def test_release_signature_checks_the_resource_helper(self):
        self.use_synthetic_team()
        app = self.app(self.root / "build/Zeus.app", "new-app")
        extra = app / "Contents/Resources/zeus-now-playing"
        extra.parent.mkdir(parents=True)
        extra.write_text("helper")
        extra.chmod(0o755)
        result = self.run_script("verify-release-signature.sh", app)
        self.assertEqual(result.returncode, 0, result.stderr)
        displayed = [c for c in self.commands() if c[:2] == ["codesign", "--display"] and c[-1] == str(extra)]
        self.assertEqual(displayed, [["codesign", "--display", "--verbose=4", str(extra)]])

    def test_release_signature_pins_team_bundle_and_verifies_the_helper(self):
        self.use_synthetic_team()
        app = self.app(self.root / "build/Zeus.app", "new-app")
        extra = app / "Contents/Resources/zeus-now-playing"
        extra.parent.mkdir(parents=True)
        extra.write_text("helper")
        extra.chmod(0o755)
        for state in ("wrong-team", "wrong-bundle"):
            with self.subTest(state=state):
                self.log.write_text("")
                result = self.run_script("verify-release-signature.sh", app, SIGNATURE_STATE=state)
                self.assertNotEqual(result.returncode, 0, result.stderr)
        self.log.write_text("")
        result = self.run_script("verify-release-signature.sh", app)
        self.assertEqual(result.returncode, 0, result.stderr)
        requirement = "certificate leaf[subject.OU] = TESTTEAM01"
        self.assertIn(["codesign", "--verify", "--strict", "-R", requirement, str(extra)], self.commands())

    def test_team_id_must_be_ten_uppercase_characters(self):
        app = self.app(self.root / "build/Zeus.app", "new-app")
        self.now_playing(app)
        path = self.root / "scripts/verify-release-signature.sh"
        original = path.read_text()
        cases = (
            ("empty-team", ""),
            ("short-team", "TEAMID123"),
            ("long-team", "TEAMID12345"),
            ("lower-team", "testteam01"),
            ("symbol-team", "TEST-TEAM1"),
        )
        for state, team in cases:
            with self.subTest(state=state):
                path.write_text(original.replace('EXPECTED_TEAM_ID="ZEUSTEAMID"', f'EXPECTED_TEAM_ID="{team}"', 1))
                result = self.run_script("verify-release-signature.sh", app, SIGNATURE_STATE=state)
                self.assertNotEqual(result.returncode, 0, result.stderr)
        path.write_text(original)

    def test_cdhash_loop_does_not_name_the_resource_helper(self):
        text = (REPO / "scripts/bundle.sh").read_text()
        loops = [line for line in text.splitlines() if line.strip().startswith("for bin in")]
        self.assertTrue(loops)
        self.assertFalse(any("zeus-now-playing" in line for line in loops))

    def test_real_entitlements_have_no_unexpanded_team_prefix(self):
        text = (REPO / "Resources/Zeus.entitlements").read_text()
        self.assertNotIn("$(AppIdentifierPrefix)", text)

    def test_dev_partition_list_omits_the_resource_helper_cdhash(self):
        # The helper reads MediaRemote and prints text. It does not open the Keychain, so its cdhash
        # must not be added to the dev partition list. The keychain file below is an empty fixture.
        self.bundle_fixture()
        home = self.root / "home"
        keychain = home / "Library/Keychains"
        keychain.mkdir(parents=True)
        (keychain / "zeus-dev.keychain-db").write_text("fixture-keychain")
        (home / ".zeus").mkdir()
        (home / ".zeus/devkeychain.pass").write_text("fixture-pass\n")
        (home / ".zeus-dev/codesign").mkdir(parents=True)
        result = self.run_script("bundle.sh", HOME=str(home))
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        targets = [Path(c[-1]).name for c in self.commands() if c[:2] == ["codesign", "-dvvv"]]
        self.assertIn("Zeus", targets)
        self.assertNotIn("zeus-now-playing", targets)

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
