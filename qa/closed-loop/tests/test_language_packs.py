"""Language packs install after the app and only from a visible choice (docs/LANGUAGE-PACKS.md)."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "Sources/Zeus"
CORE_FILE = ROOT / "Sources/ZeusCore/Languages/LanguagePack.swift"
APP_FILES = [APP / "Languages/LanguageAssets.swift", APP / "Languages/LanguagePackController.swift",
             APP / "Onboarding/OnboardingLanguagesStep.swift", APP / "Settings/GSLanguagePacksCard.swift"]


def code(path):
    return [(n, line) for n, line in enumerate(path.read_text().splitlines(), 1) if not line.strip().startswith("//")]


class LanguagePackLint(unittest.TestCase):
    def test_no_sleep_sequencing_and_no_em_dash(self):
        for path in [CORE_FILE, *APP_FILES]:
            for n, line in code(path):
                self.assertIsNone(re.search(r"\bTask\.sleep\b", line), f"{path.name}:{n}")
                self.assertNotIn("—", line.split("//")[0], f"{path.name}:{n}")

    def test_core_model_is_pure(self):
        text = "\n".join(line.split("//")[0] for _, line in code(CORE_FILE))
        for forbidden in ("import Speech", "import AppKit", "import FluidAudio", "URLSession", "UserDefaults"):
            self.assertNotIn(forbidden, text)

    def test_installs_run_serially_at_utility_priority(self):
        text = (APP / "Languages/LanguagePackController.swift").read_text()
        self.assertNotIn(".userInitiated", text)
        self.assertNotIn("TaskGroup", text)
        self.assertEqual(len(re.findall(r"Task\(priority: \.utility\)", text)), 3)

    def test_apple_asset_api_is_confined_to_the_assets_file(self):
        offenders = [str(p.relative_to(ROOT)) for p in sorted(APP.rglob("*.swift"))
                     if p.name not in ("LanguageAssets.swift", "AppleAnalyzerEngine.swift")
                     for _, line in code(p) if re.search(r"AssetInventory\.(reserve|release|assetInstallationRequest)", line)]
        self.assertEqual(offenders, [])

    def test_nothing_requests_an_install_before_onboarding_finishes_or_a_settings_tap(self):
        # Installs begin from exactly three places: the finished guide, a Settings tap and the saved consent at launch.
        controller = (APP / "Languages/LanguagePackController.swift").read_text()
        self.assertEqual(len(re.findall(r"\.installRequested\(", controller)), 2)
        callers = {str(p.relative_to(APP)) for p in APP.rglob("*.swift") for _, line in code(p)
                   if re.search(r"LanguagePackController\.shared\.startAfterOnboarding\(\)", line)}
        self.assertEqual(callers, {"Onboarding/OnboardingFlow.swift"})
        flow = (APP / "Onboarding/OnboardingFlow.swift").read_text()
        finish = flow[flow.index("private func finish()"):]
        self.assertLess(finish.index("flow.complete()"), finish.index("startAfterOnboarding()"))
        step = (APP / "Onboarding/OnboardingLanguagesStep.swift").read_text()
        self.assertNotIn("installRequested", step)
        self.assertNotIn(".install(", step)

    def test_skipping_the_step_records_no_consent(self):
        flow = (APP / "Onboarding/OnboardingFlow.swift").read_text()
        # One shared footer: on the Languages step "Set up later" declines (installs nothing) and "Continue" confirms.
        self.assertRegex(flow, r'Button\("Set up later"\) \{\s*if flow\.step == \.languages \{ LanguagePackController\.shared\.declineOnboardingChoice\(\) \}\s*flow\.skipStep\(\)')
        self.assertRegex(flow, r'Button\("Continue"\) \{\s*if flow\.step == \.languages \{ LanguagePackController\.shared\.confirmOnboardingChoice\(\) \}\s*flow\.next\(\)')
        self.assertNotIn("confirmOnboardingChoice", flow.split('Button("Set up later")')[1].split('Button("Continue")')[0])

    def test_launch_resume_is_called_without_awaiting(self):
        delegate = (APP / "App/AppDelegate.swift").read_text()
        self.assertIn("LanguagePackController.shared.resumeOnLaunch()", delegate)
        self.assertNotRegex(delegate, r"await\s+LanguagePackController")

    def test_bundle_has_no_language_data_and_strips_symbols(self):
        script = (ROOT / "scripts/bundle.sh").read_text()
        self.assertIn("strip -S -x", script)
        self.assertLess(script.index("strip -S -x"), script.index("codesign --force"))
        self.assertEqual(sorted(p.name for p in (ROOT / "Sources/Zeus/Languages").iterdir()),
                         ["LanguageAssets.swift", "LanguagePackController.swift"])

    def test_default_packs_are_the_four_requested(self):
        text = CORE_FILE.read_text()
        for raw in ('english = "en"', 'french = "fr"', 'spanish = "es"', 'portuguese = "pt"'):
            self.assertIn(raw, text)


if __name__ == "__main__":
    unittest.main()
