"""Source lint for two crashes found by launching the packaged app (CI never launches it).

1. `Bundle.module` in the app target traps in the packaged Zeus.app: SwiftPM's accessor looks
   beside Zeus.app, while scripts/bundle.sh seals Zeus_Zeus.bundle in Contents/Resources.
2. A TCC permission completion handler written inside a @MainActor type inherits main-actor
   isolation; TCC calls it on a background queue and Swift 6 traps. Only the nonisolated
   SystemAuthorization helper may pass these handlers.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "Sources/Zeus"
HELPER = APP / "App/SystemAuthorization.swift"
AUDIO_CALLBACK_APIS = re.compile(r"\.(?:installTap\(|recognitionTask\(with)")
# Enclosing types audited as not main-actor isolated (2026-11-10), plus the nonisolated helper.
AUDITED_AUDIO_FILES = {
    "Audio/OffMainAudioCallbacks.swift", "Dictation/SpeechEngines.swift", "Polyglot/PolyglotAudio.swift",
    "Polyglot/PolyglotEngines.swift", "Scribe/ScribeLiveCapture.swift", "Voice/SpeechInput.swift",
    "Voice/WakeWordListener.swift",
}
HANDLER_APIS = re.compile(r"\b(?:SFSpeechRecognizer\.requestAuthorization|INFocusStatusCenter\.default\.requestAuthorization)\s*[({]")


POINTING = APP / "Pointing"
# Pointing must advance on real events, never a sleep, and must never use the word-count clock.
POINTING_FORBIDDEN = re.compile(r"\bTask\.sleep\b|SpeechDrawingTimeline\.estimate|\.installTap\(|\brequestAccess\(|\brequestAuthorization\b|CGRequestScreenCaptureAccess|CGRequestListenEventAccess")
# System callbacks that must be installed from a nonisolated function.
POINTING_CALLBACK_APIS = re.compile(r"CGEvent\.tapCreate|addGlobalMonitorForEvents|addLocalMonitorForEvents")


def pointing_callback_offenders(text, label="sample"):
    """Lines that install a system callback outside a function declared `nonisolated`."""
    lines = text.splitlines()
    offenders = []
    for index, line in enumerate(lines):
        if line.strip().startswith("//") or not POINTING_CALLBACK_APIS.search(line):
            continue
        header = next((lines[i] for i in range(index, -1, -1) if re.search(r"\bfunc\b", lines[i])), "")
        if "nonisolated" not in header:
            offenders.append(f"{label}:{index + 1}")
    return offenders


def swift_files():
    return sorted(APP.rglob("*.swift"))


def code_lines(path):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        stripped = line.strip()
        if not stripped.startswith("//"):
            yield number, line


class SourceLint(unittest.TestCase):
    def test_app_target_never_uses_swiftpm_bundle_module(self):
        offenders = [f"{p.relative_to(ROOT)}:{n}" for p in swift_files() for n, line in code_lines(p)
                     if re.search(r"\bBundle\.module\b", line)]
        self.assertEqual(offenders, [], "use ZeusResources.bundle; Bundle.module traps in the packaged app")

    def test_tcc_completion_handlers_only_in_nonisolated_helper(self):
        offenders = [f"{p.relative_to(ROOT)}:{n}" for p in swift_files() if p != HELPER
                     for n, line in code_lines(p) if HANDLER_APIS.search(line)]
        self.assertEqual(offenders, [], "await SystemAuthorization instead of passing a TCC handler")

    def test_audio_taps_and_recognition_handlers_only_in_audited_files(self):
        # Same trap as the TCC handler: a tap block or recognition handler written in a @MainActor
        # type fails the executor check on the first buffer. New sites go through
        # OffMainAudioCallbacks, or are added here only after their enclosing type is audited.
        offenders = [f"{p.relative_to(ROOT)}:{n}" for p in swift_files()
                     if str(p.relative_to(APP)) not in AUDITED_AUDIO_FILES
                     for n, line in code_lines(p) if AUDIO_CALLBACK_APIS.search(line)]
        self.assertEqual(offenders, [], "use OffMainAudioCallbacks from @MainActor code")

    def test_every_requested_permission_has_its_info_plist_usage_string(self):
        # macOS terminates an app that requests a protected resource without the matching key.
        # Live QA found Location and Focus requests with no usage string (2026-11-10).
        import plistlib
        info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        required = {
            r"requestWhenInUseAuthorization|requestAlwaysAuthorization": "NSLocationWhenInUseUsageDescription",
            r"INFocusStatusCenter\.default\.requestAuthorization": "NSFocusStatusUsageDescription",
            r"AVCaptureDevice\.requestAccess\(for: *\.audio": "NSMicrophoneUsageDescription",
            r"AVCaptureDevice\.requestAccess\(for: *\.video|requestCamera": "NSCameraUsageDescription",
            r"SFSpeechRecognizer\.requestAuthorization": "NSSpeechRecognitionUsageDescription",
            r"requestFullAccessToEvents": "NSCalendarsFullAccessUsageDescription",
            r"requestFullAccessToReminders": "NSRemindersFullAccessUsageDescription",
        }
        missing = []
        for pattern, key in required.items():
            used = [f"{p.relative_to(ROOT)}:{n}" for p in swift_files() for n, line in code_lines(p) if re.search(pattern, line)]
            if used and not str(info.get(key, "")).strip():
                missing.append(f"{key} (used at {used[0]})")
        self.assertEqual(missing, [])

    def test_helper_is_nonisolated_and_covers_each_api(self):
        text = "\n".join(line for _, line in code_lines(HELPER))
        self.assertNotIn("@MainActor", text)
        self.assertEqual(len(HANDLER_APIS.findall(text)), 2)
        self.assertEqual(text.count("nonisolated static func"), 2)

    def test_pointing_never_sleeps_or_requests_permission_or_uses_the_estimated_clock(self):
        offenders = [f"{p.relative_to(ROOT)}:{n}" for p in sorted(POINTING.rglob("*.swift"))
                     for n, line in code_lines(p) if POINTING_FORBIDDEN.search(line)]
        self.assertEqual(offenders, [])

    def test_pointing_system_callbacks_are_installed_from_nonisolated_functions(self):
        offenders = []
        for p in sorted(POINTING.rglob("*.swift")):
            offenders += pointing_callback_offenders(p.read_text(), str(p.relative_to(ROOT)))
        self.assertEqual(offenders, [])

    def test_pointing_lint_detects_its_failure_shapes(self):
        # Fail-first samples: the exact shapes the lint exists to catch.
        self.assertTrue(POINTING_FORBIDDEN.search("try await Task.sleep(for: .seconds(1))"))
        self.assertTrue(POINTING_FORBIDDEN.search("let t = SpeechDrawingTimeline.estimate(text)"))
        self.assertTrue(POINTING_FORBIDDEN.search("CGRequestScreenCaptureAccess()"))
        bad = "@MainActor final class A {\n    func start() {\n        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ in }\n    }\n}"
        self.assertEqual(pointing_callback_offenders(bad), ["sample:3"])
        good = "enum B {\n    nonisolated static func start() {\n        CGEvent.tapCreate(tap: x)\n    }\n}"
        self.assertEqual(pointing_callback_offenders(good), [])

    def test_lint_detects_the_original_crash_shapes(self):
        # Fail-first evidence kept as a test: the exact pre-fix lines must be flagged.
        self.assertTrue(HANDLER_APIS.search("SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }"))
        self.assertTrue(HANDLER_APIS.search("INFocusStatusCenter.default.requestAuthorization { _ in }"))
        self.assertTrue(re.search(r"\bBundle\.module\b", "Bundle.module.url(forResource: name)"))


if __name__ == "__main__":
    unittest.main()
