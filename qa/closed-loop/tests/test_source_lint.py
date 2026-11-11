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


def swift_files():
    return sorted(APP.rglob("*.swift"))


def code_lines(path):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        stripped = line.strip()
        if not stripped.startswith("//"):
            yield number, line


def strip_trailing_comment(line):
    """The code part of a Swift line: drops a `//` comment that starts outside a string literal."""
    in_string = False
    escaped = False
    for index, char in enumerate(line):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char == "/" and line[index + 1:index + 2] == "/":
            return line[:index]
    return line


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

    def test_user_visible_swift_strings_have_no_em_dash(self):
        # House style: no em dashes in anything a person reads. Only the code part of each line is checked:
        # a trailing `// comment` and whole-line comments may use one. ZeusCore is out of scope here because
        # its dash handling (parsers that must recognise a dash) is covered by its own tests.
        offenders = [f"{p.relative_to(ROOT)}:{n}" for p in swift_files() for n, line in code_lines(p)
                     if "—" in strip_trailing_comment(line)]
        self.assertEqual(offenders, [], "rewrite with a comma, colon or full stop")

    def test_em_dash_lint_is_precise(self):
        self.assertEqual(strip_trailing_comment('let a = 1 // fine — a comment'), "let a = 1 ")
        self.assertIn("—", strip_trailing_comment('Text("Overdue — do this next")'))
        self.assertIn("—", strip_trailing_comment('Text("see https://x.test — now") // ok'))
        self.assertNotIn("—", strip_trailing_comment('Text("ok") // https://x.test — note'))

    def test_helper_is_nonisolated_and_covers_each_api(self):
        text = "\n".join(line for _, line in code_lines(HELPER))
        self.assertNotIn("@MainActor", text)
        self.assertEqual(len(HANDLER_APIS.findall(text)), 2)
        self.assertEqual(text.count("nonisolated static func"), 2)

    def test_lint_detects_the_original_crash_shapes(self):
        # Fail-first evidence kept as a test: the exact pre-fix lines must be flagged.
        self.assertTrue(HANDLER_APIS.search("SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }"))
        self.assertTrue(HANDLER_APIS.search("INFocusStatusCenter.default.requestAuthorization { _ in }"))
        self.assertTrue(re.search(r"\bBundle\.module\b", "Bundle.module.url(forResource: name)"))


if __name__ == "__main__":
    unittest.main()
