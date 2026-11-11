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


# Speaker recognition (docs/SPEAKER-IDENTIFICATION.md): the WeSpeaker model downloads only from an explicit click.
SPEAKER_MODEL_FILE = "Scribe/ScribeVoiceModel.swift"
SPEAKER_SETTINGS_FILE = "Settings/GSSpeakerRecognitionCard.swift"
SPEAKER_CORE = ROOT / "Sources/ZeusCore/Scribe"
SPEAKER_CORE_FILES = ["ScribeVoiceEmbedding.swift", "ScribeDiarizer.swift", "ScribeSpeakerNames.swift", "ScribeSpeakerCorrection.swift",
                      "ScribeVoiceLibrary.swift", "ScribeNameSuggester.swift"]


class SpeakerRecognitionLint(unittest.TestCase):
    def test_diarizer_models_are_named_only_in_the_model_file(self):
        offenders = [f"{p.relative_to(ROOT)}:{n}" for p in swift_files() if str(p.relative_to(APP)) != SPEAKER_MODEL_FILE
                     for n, line in code_lines(p) if re.search(r"\bDiarizerModels\b", line)]
        self.assertEqual(offenders, [], "only ScribeVoiceModel.swift may touch DiarizerModels")

    def test_download_is_reachable_only_from_the_settings_click(self):
        # The download call lives in the model file; its controller's prepare() is called by the Settings card only.
        download = [f"{p.relative_to(ROOT)}:{n}" for p in swift_files() if str(p.relative_to(APP)) != SPEAKER_MODEL_FILE
                    for n, line in code_lines(p) if re.search(r"SpeakerModelStore\.download\b", line)]
        self.assertEqual(download, [])
        prepare = [f"{p.relative_to(ROOT)}:{n}" for p in swift_files()
                   if str(p.relative_to(APP)) not in (SPEAKER_MODEL_FILE, SPEAKER_SETTINGS_FILE)
                   for n, line in code_lines(p) if re.search(r"SpeakerModelController\b", line)]
        self.assertEqual(prepare, [], "no launch or meeting path may start the model download")
        card = "\n".join(line for _, line in code_lines(APP / SPEAKER_SETTINGS_FILE))
        self.assertEqual(len(re.findall(r"model\.prepare\(\)", card)), 2)
        self.assertIn('Button("Download")', card)
        self.assertIn("Only save voices of people who agreed.", card)

    def test_meeting_code_only_loads_a_model_that_is_already_on_disk(self):
        model = "\n".join(line for _, line in code_lines(APP / SPEAKER_MODEL_FILE))
        load = model[model.index("static func loadEmbedder"):]
        self.assertLess(load.index("guard isDownloaded"), load.index("DiarizerModels.load"))

    def test_speaker_files_do_not_sleep_and_core_stays_free_of_fluidaudio(self):
        for name in (SPEAKER_MODEL_FILE, SPEAKER_SETTINGS_FILE):
            offenders = [n for n, line in code_lines(APP / name) if re.search(r"\bTask\.sleep\b", line)]
            self.assertEqual(offenders, [], name)
        for name in SPEAKER_CORE_FILES:
            lines = list(code_lines(SPEAKER_CORE / name))
            self.assertEqual([n for n, line in lines if "import FluidAudio" in line], [], name)
            self.assertEqual([n for n, line in lines if "\u2014" in strip_trailing_comment(line)], [], name)
            self.assertEqual([n for n, line in lines if re.search(r"\bTask\.sleep\b", line)], [], name)

    def test_saved_voices_never_leave_the_mac(self):
        for name in ("ScribeVoiceLibrary.swift",):
            text = "\n".join(line for _, line in code_lines(SPEAKER_CORE / name))
            self.assertNotIn("URLSession", text)
            self.assertNotIn("Second Brain", text)
        self.assertIn('appendingPathComponent("Voices"', "\n".join(line for _, line in code_lines(SPEAKER_CORE / "ScribeVoiceLibrary.swift")))

    def test_speaker_lint_detects_its_failure_shapes(self):
        self.assertTrue(re.search(r"\bDiarizerModels\b", "let m = try await DiarizerModels.download()"))
        self.assertTrue(re.search(r"SpeakerModelStore\.download\b", "try await SpeakerModelStore.download { _ in }"))
        self.assertTrue(re.search(r"SpeakerModelController\b", "SpeakerModelController.shared.prepare()"))


# --- Settings must never freeze (REG-225) -------------------------------------------------------------
# A blocking wait on the main thread freezes the window. These primitives are banned in app sources
# unless the file is audited as background-only (or a bounded quit-time wait) and says why.
SOURCES = ROOT / "Sources"
BLOCKING_PATTERNS = {
    "DispatchQueue.main.sync": re.compile(r"DispatchQueue\.main\.sync\b"),
    "semaphore or group wait": re.compile(r"\.wait\(\s*(?:timeout:|\))"),
    "waitUntilExit": re.compile(r"\bwaitUntilExit\(\)"),
}
AUDITED_BLOCKING_FILES = {
    "Zeus/App/PermissionsModel.swift": "Automation checks wait on global queues, bounded by a 1 s timeout, never on main.",
    "Zeus/Prompter/PresenterNotesController.swift": "OsascriptRunner and PPTXArchive run only inside Task.detached.",
    "Zeus/Brain/SpotlightClient.swift": "mdfind runs only inside Task.detached (VoiceTurnController).",
    "Zeus/Insomnia/InsomniaController.swift": "Quit-time wait for the Insomnia queue, bounded to 3 s.",
    "Zeus/Voice/KokoroWorkerSession.swift": "Child reaping on the worker's own queue and awaited tasks.",
    "Zeus/Watch/ZeusWatchRunner.swift": "Child wait inside a continuation on a global queue, killed after 3 s.",
    "Zeus/App/KeychainSelfTest.swift": "Command-line self test: no window exists.",
    "Zeus/Voice/VoiceSample.swift": "Command-line sample mode: no window exists.",
    "ZeusCore/Insomnia/InsomniaCommands.swift": "ProcessCommandRunner runs on the Insomnia serial queue; every wait has a timeout.",
    "ZeusCore/Diagnostics/FlightRecorder.swift": "The ditto zip is exported from Task.detached (GSDiagnosticsLogs).",
}
KEYCHAIN_MODULE = "ZeusCore/Keychain/"


def blocking_offenders(text, label="sample"):
    """`label:line` for each banned blocking call in the code part of `text`."""
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        code = strip_trailing_comment(line)
        if code.strip().startswith("//"):
            continue
        if any(pattern.search(code) for pattern in BLOCKING_PATTERNS.values()):
            found.append(f"{label}:{number}")
    return found


class SettingsNeverFreezeLint(unittest.TestCase):
    def test_no_blocking_waits_outside_audited_files(self):
        offenders = []
        for path in sorted(SOURCES.rglob("*.swift")):
            relative = path.relative_to(SOURCES).as_posix()
            if relative in AUDITED_BLOCKING_FILES:
                continue
            offenders += blocking_offenders(path.read_text(), relative)
        self.assertEqual(offenders, [], "blocking call outside an audited background-only file")

    def test_audited_files_exist_and_still_need_their_entry(self):
        for relative, reason in AUDITED_BLOCKING_FILES.items():
            path = SOURCES / relative
            self.assertTrue(path.exists(), f"{relative} is gone: drop its allowlist entry")
            self.assertTrue(reason.strip())
            self.assertTrue(blocking_offenders(path.read_text(), relative), f"{relative} no longer blocks: drop its entry")

    def test_keychain_is_read_only_through_the_keychain_module(self):
        offenders = []
        for path in sorted(SOURCES.rglob("*.swift")):
            relative = path.relative_to(SOURCES).as_posix()
            if relative.startswith(KEYCHAIN_MODULE):
                continue
            offenders += [f"{relative}:{n}" for n, line in code_lines(path) if "SecItemCopyMatching" in strip_trailing_comment(line)]
        self.assertEqual(offenders, [], "SecItemCopyMatching belongs in ZeusCore/Keychain (KeychainStore caches it)")

    def test_settings_pages_never_read_the_login_items_service_in_a_view(self):
        # SMAppService.status is a synchronous daemon round trip: only SettingsStore.swift may touch it.
        offenders = []
        for path in swift_files():
            relative = path.relative_to(APP).as_posix()
            if relative == "App/SettingsStore.swift":
                continue
            offenders += [f"{relative}:{n}" for n, line in code_lines(path) if "SMAppService.mainApp" in strip_trailing_comment(line)]
        self.assertEqual(offenders, [])

    def test_every_settings_card_and_page_is_placed_on_a_page(self):
        """A card or page that is defined but never instantiated cannot be reached (the Language packs and
        Speaker recognition cards were once orphaned this way). Intentional exceptions are listed by name."""
        # IntegrationsPage is the superseded integrations page (AIConnectionsPage is routed); left in place, reported.
        allowed_unplaced = {"IntegrationsPage"}
        defined = {}
        for folder in ("Settings", "App"):
            for path in sorted((APP / folder).glob("*.swift")):
                for _, line in code_lines(path):
                    match = re.match(r"\s*(?:private |fileprivate )?struct (\w+(?:Card|SettingsPage|Page))\b", line)
                    if match and (folder == "Settings" or path.name.endswith("Pages.swift") or path.name.endswith("Settings.swift")):
                        defined[match.group(1)] = path
        self.assertIn("LanguagePacksCard", defined)
        self.assertIn("SpeakerRecognitionCard", defined)
        orphans = []
        for name, home in sorted(defined.items()):
            if name in allowed_unplaced:
                continue
            use = re.compile(rf"\b{name}\s*[({{]")
            placed = any(use.search(strip_trailing_comment(line))
                         for path in swift_files() for _, line in code_lines(path)
                         if not re.match(r"\s*(?:private |fileprivate )?struct ", line))
            if not placed:
                orphans.append(f"{name} ({home.relative_to(APP).as_posix()})")
        self.assertEqual(orphans, [], "defined but never placed on a Settings page: add it to a page or list it in allowed_unplaced")

    def test_blocking_lint_detects_its_failure_shapes(self):
        self.assertTrue(blocking_offenders("DispatchQueue.main.sync { work() }"))
        self.assertTrue(blocking_offenders("let r = semaphore.wait(timeout: .now() + 1)"))
        self.assertTrue(blocking_offenders("done.wait()"))
        self.assertTrue(blocking_offenders("process.waitUntilExit()"))
        self.assertFalse(blocking_offenders("case .wait(let ms): return ms"))
        self.assertFalse(blocking_offenders("// done.wait() would block"))
        self.assertFalse(blocking_offenders('let note = "never call process.waitUntilExit()" // x'.replace("waitUntilExit()", "wait")))


# "laya" as its own word or name part (not "playback" or "overlay a..."): case-insensitive.
LAYA_WORD = re.compile(r"(?<![A-Za-z])[Ll][Aa][Yy][Aa](?![a-z])")
# The one allowed spelling: the owner's existing Kokoro model folder is literally named jarvis-laya-backend.
LAYA_EXTERNAL_FOLDER = "jarvis-laya-backend"


def laya_offenders(text, label="sample"):
    return [f"{label}:{n}" for n, line in enumerate(text.splitlines(), 1)
            if LAYA_WORD.search(line.replace(LAYA_EXTERNAL_FOLDER, ""))]


class LayaRemovedLint(unittest.TestCase):
    """The Laya local decision server was removed; Jev is the only model stage of instant commands."""

    def test_sources_never_mention_laya(self):
        offenders = []
        for path in sorted((ROOT / "Sources").rglob("*.swift")):
            offenders += laya_offenders(path.read_text(), path.relative_to(ROOT).as_posix())
        self.assertEqual(offenders, [], "Laya was removed; Jev is the only decision stage")

    def test_laya_lint_detects_its_failure_shapes(self):
        self.assertTrue(laya_offenders("case laya, jev"))
        self.assertTrue(laya_offenders("LayaHelper.shared.shutdown()"))
        self.assertTrue(laya_offenders("// Laya answers on this Mac"))
        self.assertTrue(laya_offenders('exec("laya-serve")'))
        self.assertFalse(laya_offenders("let playback = overlayAnimation"))
        self.assertFalse(laya_offenders('path("AI-Brain-build/jarvis-laya-backend/models")'))


# "Talk to Zeus" latency (owner run of build 0405391: four engines tried one after another, 85 s of silence).
VOICE_TURN = APP / "App/VoiceTurnController.swift"
CLAUDE_PROVIDER = APP / "Brain/Providers/ClaudeCLIProvider.swift"
TURN_RACE_CORE = ROOT / "Sources/ZeusCore/Brain/TurnRace.swift"


class VoiceLatencyLint(unittest.TestCase):
    def _turn_text(self):
        return "\n".join(line for _, line in code_lines(VOICE_TURN))

    def test_engines_are_raced_in_parallel_never_tried_one_after_another(self):
        text = self._turn_text()
        self.assertIn("FastRaceRun(", text)
        self.assertNotRegex(text, r"while\s+cursor\s*<\s*candidates\.count", "sequential fallback loop is back")

    def test_no_network_probe_or_warm_wait_before_the_engines_start(self):
        text = self._turn_text()
        run_turn = text[text.index("private func runTurn"):text.index("VoiceAnswerLatency.beginTurn()")]
        self.assertNotIn("OllamaHTTPProbe", run_turn)
        self.assertNotIn("awaitIfNeeded", run_turn)

    def test_first_text_budget_is_at_most_eight_seconds(self):
        core = "\n".join(line for _, line in code_lines(TURN_RACE_CORE))
        budget = int(re.search(r"firstTextBudgetMs\s*=\s*([0-9_]+)", core).group(1).replace("_", ""))
        self.assertLessEqual(budget, 8000)
        filler = int(re.search(r"fillerMs\s*=\s*([0-9_]+)", core).group(1).replace("_", ""))
        self.assertLessEqual(filler, 900)

    def test_spoken_claude_launch_is_lean(self):
        text = "\n".join(line for _, line in code_lines(CLAUDE_PROVIDER))
        self.assertIn('"--safe-mode"', text)
        self.assertIn('"--tools", ""', text)
        # The help probe must use the located binary: a GUI app's PATH has no ~/.local/bin.
        self.assertNotIn('"/usr/bin/env"', text)

    def test_latency_lint_detects_its_failure_shapes(self):
        self.assertTrue(re.search(r"while\s+cursor\s*<\s*candidates\.count", "while cursor < candidates.count {"))


if __name__ == "__main__":
    unittest.main()
