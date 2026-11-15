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
TILING = APP / "Tiling"
# Pointing must advance on real events, never a sleep, and must never use the word-count clock.
POINTING_FORBIDDEN = re.compile(r"\bTask\.sleep\b|SpeechDrawingTimeline\.estimate|\.installTap\(|\brequestAccess\(|\brequestAuthorization\b|CGRequestScreenCaptureAccess|CGRequestListenEventAccess")
# System callbacks that must be installed from a nonisolated function (Pointing and Tiling both follow this).
POINTING_CALLBACK_APIS = re.compile(r"CGEvent\.tapCreate|addGlobalMonitorForEvents|addLocalMonitorForEvents|AXObserverCreate")


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


# The tiling tap consumes keys, so the thread that services it must never be the main thread: the window server holds
# every keystroke in every app until the tap callback runs, and Accessibility passes run on main.
MAIN_RUN_LOOP = re.compile(r"CFRunLoopGetMain\s*\(|\bRunLoop\.main\b")


def main_run_loop_offenders(text, label="sample"):
    """Lines that name the main run loop, where a tap source could be added to it."""
    return [f"{label}:{index + 1}" for index, line in enumerate(text.splitlines())
            if not line.strip().startswith("//") and MAIN_RUN_LOOP.search(strip_trailing_comment(line))]


def main_run_loop_offenders_under(directory):
    offenders = []
    for p in sorted(directory.rglob("*.swift")):
        offenders += main_run_loop_offenders(p.read_text(), str(p.relative_to(directory.parent)))
    return offenders


def callback_offenders_under(directory):
    """Every system-callback install under `directory` that is not in a nonisolated function."""
    offenders = []
    for p in sorted(directory.rglob("*.swift")):
        offenders += pointing_callback_offenders(p.read_text(), str(p.relative_to(directory.parent)))
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
    def test_every_one_time_tab_upgrade_saves_the_row(self):
        # A row upgrade that sets its flag but is missing from the save condition is lost on relaunch.
        text = (APP / "TopBar/TopBarModel.swift").read_text()
        flags = re.findall(r"let (add\w+|reorder) = !defaults\.bool\(forKey: \"topBar\.row", text)
        save = re.search(r"if (reorder \|\|[^{]+)\{", text)
        self.assertTrue(flags and save, "tab upgrade flags or save condition not found")
        saved = {name.strip() for name in save.group(1).split("||")}
        self.assertEqual(sorted(set(flags) - saved), [])

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
            r"AudioHardwareCreateProcessTap": "NSAudioCaptureUsageDescription",
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

    def test_tiling_system_callbacks_are_installed_from_nonisolated_functions(self):
        self.assertEqual(callback_offenders_under(TILING), [])

    def test_the_tiling_tap_source_is_never_added_to_the_main_run_loop(self):
        self.assertEqual(main_run_loop_offenders_under(TILING), [])

    def test_main_run_loop_lint_detects_its_failure_shapes(self):
        # Fail-first samples: the exact shape the first tiling tap had, and the ones that mean the same thing.
        bad = "nonisolated func start() {\n    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)\n}\n"
        self.assertEqual(main_run_loop_offenders(bad), ["sample:2"])
        self.assertEqual(main_run_loop_offenders("RunLoop.main.add(timer, forMode: .common)"), ["sample:1"])
        self.assertEqual(main_run_loop_offenders("CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)"), ["sample:1"])
        good = "nonisolated func install(on loop: CFRunLoop) {\n    CFRunLoopAddSource(loop, source, .commonModes)\n}\n"
        self.assertEqual(main_run_loop_offenders(good), [])
        self.assertEqual(main_run_loop_offenders("// never CFRunLoopGetMain() here\nlet loop = CFRunLoopGetCurrent()"), [])
        self.assertEqual(main_run_loop_offenders("let loop = CFRunLoopGetCurrent() // not CFRunLoopGetMain()"), [])

    def test_pointing_lint_detects_its_failure_shapes(self):
        # Fail-first samples: the exact shapes the lint exists to catch.
        self.assertTrue(POINTING_FORBIDDEN.search("try await Task.sleep(for: .seconds(1))"))
        self.assertTrue(POINTING_FORBIDDEN.search("let t = SpeechDrawingTimeline.estimate(text)"))
        self.assertTrue(POINTING_FORBIDDEN.search("CGRequestScreenCaptureAccess()"))
        bad = "@MainActor final class A {\n    func start() {\n        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ in }\n    }\n}"
        self.assertEqual(pointing_callback_offenders(bad), ["sample:3"])
        good = "enum B {\n    nonisolated static func start() {\n        CGEvent.tapCreate(tap: x)\n    }\n}"
        self.assertEqual(pointing_callback_offenders(good), [])

    def test_tiling_lint_detects_its_failure_shapes(self):
        # Fail-first samples: a tap installed from a main-actor function under a Tiling folder is reported.
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "Tiling"
            folder.mkdir()
            (folder / "Bad.swift").write_text(
                "@MainActor final class K {\n    func start() {\n"
                "        CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap)\n    }\n}\n")
            self.assertEqual(callback_offenders_under(folder), ["Tiling/Bad.swift:3"])
            (folder / "Bad.swift").write_text(
                "enum K {\n    nonisolated func start() {\n        CGEvent.tapCreate(tap: .cgSessionEventTap)\n    }\n}\n")
            self.assertEqual(callback_offenders_under(folder), [])
        # The observer API the later Accessibility upgrade will use is watched too.
        observer = "@MainActor final class K {\n    func watch() {\n        AXObserverCreate(pid, callback, &observer)\n    }\n}"
        self.assertEqual(pointing_callback_offenders(observer), ["sample:3"])
        fine = "enum K {\n    nonisolated func watch() {\n        AXObserverCreate(pid, callback, &observer)\n    }\n}"
        self.assertEqual(pointing_callback_offenders(fine), [])

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
    "Zeus/Tiling/TilingRunLoopThread.swift": "stop() waits for the tap thread to remove its tap. That thread runs only the tap callback and the teardown, so it ends in microseconds, and the wait is bounded to 2 s.",
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

    def test_selftests_have_no_docstrings(self):
        # unittest -v prints a test docstring on its own line, which splits "name ... ok" and makes the
        # closed-loop gate count fewer passing cases than ran ("Python cases missing/duplicated/skipped").
        import re
        offenders = []
        for path in sorted((ROOT / "qa/closed-loop/tests").glob("test_*.py")):
            text = path.read_text()
            for match in re.finditer(r"^\s+def (test_\w+)\(self[^)]*\):\s*\n\s+(\"\"\"|\'\'\')", text, re.MULTILINE):
                offenders.append(f"{path.name}:{match.group(1)}")
        self.assertEqual(offenders, [], "use a comment, not a docstring, in closed-loop selftests")

    def test_every_settings_card_and_page_is_placed_on_a_page(self):
        # A card or page that is defined but never instantiated cannot be reached (the Language packs and
        # Speaker recognition cards were once orphaned this way). Intentional exceptions are listed by name.
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

    def test_nothing_warms_at_launch_and_the_talk_key_warms_the_brain(self):
        text = self._turn_text()
        init = text[text.index("init("):text.index("private func armAhead")]
        for forbidden in ("prewarm", "BrainLaunchWarm", "ClaudeFlags.warm", "warmSelectedVoice"):
            self.assertNotIn(forbidden, init, f"{forbidden} runs at launch")
        press = text[text.index("func press()"):text.index("func release()")]
        self.assertIn("KeyDownWarmer.talkKeyDown()", press)
        self.assertIn("abortBusy()", press)

    def test_every_turn_writes_one_voice_latency_line_without_text(self):
        latency = (ROOT / "Sources/Zeus/Voice/VoiceLatency.swift").read_text()
        self.assertIn('NSLog("[ZEUS] voice-latency %@"', latency)
        self.assertNotIn("transcript:", latency)
        text = self._turn_text()
        for stage in (".transcriptFinal", ".requestSent", ".firstToken", ".firstSentence"):
            self.assertIn(f"VoiceLatency.shared.mark({stage})", text)
        speaker = (ROOT / "Sources/Zeus/Voice/Speaker.swift").read_text()
        self.assertIn("VoiceLatency.shared.mark(.firstAudio)", speaker)
        self.assertIn("VoiceLatency.shared.mark(.ttsRequest)", speaker)

    def test_the_voice_is_never_designed_without_a_tap(self):
        for path in (ROOT / "Sources/Zeus").rglob("*.swift"):
            self.assertNotIn("designUltronVoiceOnce", path.read_text(), str(path))

    def test_latency_lint_detects_its_failure_shapes(self):
        self.assertTrue(re.search(r"while\s+cursor\s*<\s*candidates\.count", "while cursor < candidates.count {"))



import importlib.util as _ilu

_VL_SPEC = _ilu.spec_from_file_location("voice_latency", ROOT / "scripts/voice-latency.py")
voice_latency = _ilu.module_from_spec(_VL_SPEC)
_VL_SPEC.loader.exec_module(voice_latency)

LINE = ('2026-11-11T14:00:01.100-05:00 voice-latency turn=a1 key_up=0 transcript=300 request=320 first_token=780 '
        'first_sentence=1000 tts_request=1010 first_audio=1350 turn_end=4800 ttfa=1350 brain=anthropic-api '
        'model=claude-haiku-5-5 tts=elevenlabs/eleven_flash_v2_5 voice=v effect=60 reason="auto: best, low delay"')


class VoiceLatencyScript(unittest.TestCase):
    def test_parses_a_log_line_with_a_quoted_reason(self):
        row = voice_latency.parse(LINE)
        self.assertEqual(row["turn"], "a1")
        self.assertEqual(row["at"], "14:00:01")
        self.assertEqual(voice_latency.number(row, "ttfa"), 1350)
        self.assertEqual(row["reason"], "auto: best, low delay")

    def test_ignores_other_lines_and_dashes(self):
        self.assertIsNone(voice_latency.parse("2026-11-11T14:00:09.000-05:00 speak engine=x"))
        row = voice_latency.parse(LINE.replace("ttfa=1350", "ttfa=-"))
        self.assertIsNone(voice_latency.number(row, "ttfa"))

    def test_percentiles_interpolate(self):
        self.assertEqual(voice_latency.percentile([], 0.5), None)
        self.assertEqual(voice_latency.percentile([100], 0.9), 100)
        self.assertEqual(voice_latency.percentile([100, 200], 0.5), 150)
        self.assertEqual(voice_latency.percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.9), 9.1)

    def test_summary_reports_p50_p90_and_the_route_target(self):
        rows = [voice_latency.parse(LINE.replace("ttfa=1350", f"ttfa={ms}")) for ms in (1000, 1100, 1200, 2000)]
        text = voice_latency.summary(rows)
        self.assertIn("key-up -> first audio: p50 1150 ms", text)
        self.assertIn("target p50 for this route: 1200 ms -> PASS", text)

    def test_log_line_never_needs_a_transcript(self):
        row = voice_latency.parse(LINE)
        self.assertNotIn("transcript_text", row)


# Third state-machine pass (docs/STATE-MACHINES.md): wiring the pure reducers cannot see.


def pass3_source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def pass3_function_body(text, signature):
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 0
    for index in range(brace, len(text)):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        if depth == 0:
            return text[brace:index]
    raise AssertionError(signature)


class Pass3VoiceTurnWiring(unittest.TestCase):
    TEXT = pass3_source("Sources/Zeus/App/VoiceTurnController.swift")

    def test_turn_flag_is_a_latest_run_not_a_bool(self):
        self.assertIn("private var turnRun = LatestRun()", self.TEXT)
        self.assertNotRegex(self.TEXT, r"turnRunning\s*=\s*(true|false)")

    def test_press_stops_the_hands_free_timer(self):
        body = pass3_function_body(self.TEXT, "func press() -> Bool")
        self.assertIn("handsFreeTask?.cancel()", body)
        self.assertIn("turnRun.invalidate()", body)

    def test_wake_turn_stops_the_previous_answer_and_its_deep_follow_up(self):
        body = pass3_function_body(self.TEXT, "func wakeTurn(request: String)")
        self.assertIn("fastRace?.cancel()", body)
        self.assertIn("ahead.cancel()", body)


class Pass3SpeakerWiring(unittest.TestCase):
    TEXT = pass3_source("Sources/Zeus/Voice/Speaker.swift")

    def test_provider_failures_are_not_recorded_for_a_cancelled_line(self):
        notes = re.findall(r"^(.*noteProviderFailure\(.*)$", self.TEXT, re.M)
        self.assertGreaterEqual(len(notes), 4)
        for line in notes:
            self.assertIn("countsAsFailure()", line, line)

    def test_rendered_files_are_dropped_after_a_cancel(self):
        for engine in ("speakKokoro", "speakChatterbox"):
            body = pass3_function_body(self.TEXT, f"private func {engine}(")
            self.assertIn("SpeechAttemptPolicy.mayPlay", body, engine)


class Pass3RaceRunWiring(unittest.TestCase):
    def test_only_live_tiers_count_as_failed(self):
        text = pass3_source("Sources/Zeus/Brain/FastRaceRun.swift")
        self.assertGreaterEqual(text.count("guard state.isLive(id) else { break }"), 2)


class Pass3RecordlyWiring(unittest.TestCase):
    def test_leaving_the_record_page_cancels_the_countdown(self):
        self.assertIn(".onDisappear { recordly.pageDisappeared() }", pass3_source("Sources/Zeus/Recordly/RecordlyPage.swift"))
        body = pass3_function_body(pass3_source("Sources/Zeus/Recordly/RecordlyController.swift"), "func pageDisappeared()")
        self.assertIn("countdown.send(.cancel)", body)


class Pass3NotchWiring(unittest.TestCase):
    TEXT = pass3_source("Sources/Zeus/Notch/NotchController.swift")

    def test_alert_timers_pause_while_the_capsule_is_covered(self):
        self.assertIn("model.alerts.setSuspended(presentation != .closed", pass3_function_body(self.TEXT, "func show(_ presentation"))

    def test_a_snoozed_alert_returns_even_when_the_notch_is_open(self):
        self.assertIn("whileOpen: true", pass3_function_body(self.TEXT, "func snoozeAlert("))


OPEN_ON_CLICK_RETURN = "if self?.openOnClick() == true { return }"
HOVER_GATE = "guard NotchOpenRules.opensOnHover(Self.openTrigger) else"


def click_open_returns_before_outside(text):
    """True when the global mouse-down closure returns after a click that opened the notch, before
    clickedOutside() can dismiss the panel that click just opened."""
    returned = text.find(OPEN_ON_CLICK_RETURN)
    outside = text.find("self?.clickedOutside()")
    return returned != -1 and outside != -1 and returned < outside


def local_mouse_down_opens_on_click(text):
    return re.search(r"addLocalMonitorForEvents\(matching: \[\.leftMouseDown\]\)[^}]*?openOnClick\(\)", text) is not None


def hover_gate_precedes_the_dwell(body):
    """True when click mode returns before the hover dwell that opens the panel."""
    gate = body.find(HOVER_GATE)
    dwell = body.find("hoverTask = Task")
    shortcut = body.find("guard topBar != nil else { show(.panel); return }")
    return gate != -1 and gate < dwell and gate < shortcut


def check_precedes(body, first, second):
    return first in body and second in body and body.index(first) < body.index(second)


class Pass4IslandWiring(unittest.TestCase):
    """Island click open, corner overlay, music display hold and lyrics privacy: wiring no pure rule can see."""
    NOTCH = pass3_source("Sources/Zeus/Notch/NotchController.swift")

    def test_a_click_that_opens_the_notch_returns_before_clicked_outside(self):
        start = pass3_function_body(self.NOTCH, "func start()")
        self.assertTrue(click_open_returns_before_outside(start))

    def test_click_mode_also_listens_while_a_zeus_window_is_frontmost(self):
        self.assertTrue(local_mouse_down_opens_on_click(pass3_function_body(self.NOTCH, "func start()")))

    def test_hovering_never_opens_the_notch_in_click_mode(self):
        self.assertTrue(hover_gate_precedes_the_dwell(pass3_function_body(self.NOTCH, "private func mouseMoved()")))

    def test_a_click_opens_only_through_the_pure_rule_and_a_known_surface(self):
        body = pass3_function_body(self.NOTCH, "private func openOnClick() -> Bool")
        self.assertIn("topBar != nil || !model.sessions.isEmpty || model.approval != nil", body)
        self.assertTrue(check_precedes(body, "NotchOpenRules.opensOnClick(trigger: Self.openTrigger, panelIsOpen: model.presentation == .panel", "show(.panel)"))

    def test_the_corner_overlay_follows_screen_sharing_and_the_two_settings(self):
        sharing = pass3_source("Sources/Zeus/App/ZeusWindowSharing.swift")
        self.assertIn("ScreenCornerOverlay.shared.applyScreenSharePolicy(visibleInShare: visible)", pass3_function_body(sharing, "static func refresh("))
        delegate = pass3_source("Sources/Zeus/App/AppDelegate.swift")
        self.assertIn("ScreenCornerOverlay.shared.start()", delegate)
        self.assertIn('case "screen.roundBottomCorners", "screen.cornerRadius": ScreenCornerOverlay.shared.settingsChanged()', delegate)

    def test_the_corner_overlay_draws_only_on_notched_screens_and_keeps_unchanged_panels(self):
        overlay = pass3_source("Sources/Zeus/Notch/ScreenCornerOverlay.swift")
        self.assertIn("ScreenCorners.draws(hasNotch: Self.hasNotch(screen), enabled: enabled)", overlay)
        self.assertIn("guard wanted != placements else { return }", pass3_function_body(overlay, "private func rebuild()"))
        make = pass3_function_body(overlay, "static func makePanel(")
        self.assertIn("ScreenCornerPanelFlags.standard", make)
        self.assertIn("ZeusWindowSharing.apply(to: panel", make)
        self.assertIn("ignoresMouseEvents: true", overlay)

    def test_the_music_hold_takes_its_own_display_assertion_that_releases_itself(self):
        hold = pass3_source("Sources/Zeus/TopBar/MusicAwakeHold.swift")
        body = pass3_function_body(hold, "static func createAssertion(")
        self.assertIn("IOPMAssertionCreateWithDescription(", body)
        self.assertIn('"PreventUserIdleDisplaySleep"', body)
        self.assertIn('"TimeoutActionRelease"', body)
        self.assertIn("timeout,", body)
        self.assertNotIn("KeepAwakeSession.shared.begin", hold)

    def test_lyrics_are_never_requested_while_the_privacy_setting_is_off(self):
        text = pass3_source("Sources/Zeus/TopBar/LyricsViews.swift")
        load = pass3_function_body(text, "func load(for playing: NowPlaying?)")
        self.assertIn("send(.load(enabled: isEnabled()", load, "the flow decides with the privacy switch")
        self.assertIn("enabled: @escaping @MainActor () -> Bool = { LyricsStore.enabled }", text,
                      "the switch the store asks is the privacy setting unless a test gives its own")
        run = pass3_function_body(text, "private func run(_ query: LRCLIBQuery) async")
        self.assertTrue(check_precedes(run, "guard mayRequest(key) else { return }", "Self.fetch("),
                        "the switch is checked before every request")
        self.assertIn("retryPlan(for: key, now: Date(), enabled: self?.isEnabled() ?? false)", text)
        self.assertIn("let enabled = isEnabled()", pass3_function_body(text, "private func mayRequest(_ key: String) -> Bool"))
        self.assertEqual(text.count("self?.run("), 1, "only the flow's lookup effect may start a request")

    def test_the_sampling_reader_uses_the_occlusion_aware_rule(self):
        text = pass3_source("Sources/Zeus/Perf/SamplingHold.swift")
        body = pass3_function_body(text, "override func viewDidMoveToWindow()")
        self.assertIn("SamplingVisibility.reading(after: name", body)
        self.assertIn("onChange(SamplingVisibility.isSeen(window))", body)
        self.assertNotIn("WindowVisibility.reading", body)
        self.assertNotIn("WindowVisibility.isVisible", body)

    def test_the_diagnostics_card_hears_thermal_changes_on_the_main_queue_from_one_publisher(self):
        text = pass3_source("Sources/Zeus/Settings/GSLiveDiagnosticsCard.swift")
        self.assertIn(".onReceive(Self.thermalPublisher)", text)
        self.assertIn("static let thermalPublisher = thermalChanges()", text)
        factory = pass3_function_body(text, "static func thermalChanges(")
        self.assertIn(".receive(on: DispatchQueue.main)", factory)
        self.assertEqual(text.count("publisher(for: ProcessInfo.thermalStateDidChangeNotification)"), 1,
                         "only thermalChanges(center:) may subscribe, and it hops to the main queue")

    def test_the_island_lints_detect_their_failure_shapes(self):
        good = f"""func start() {{
            addGlobalMonitorForEvents(matching: [.leftMouseDown]) {{ _ in
                {OPEN_ON_CLICK_RETURN}
                self?.clickedOutside()
            }}
            addLocalMonitorForEvents(matching: [.leftMouseDown]) {{ event in
                MainActor.assumeIsolated {{ _ = self?.openOnClick() }}
                return event
            }}
        }}"""
        self.assertTrue(click_open_returns_before_outside(good))
        self.assertTrue(local_mouse_down_opens_on_click(good))
        self.assertFalse(click_open_returns_before_outside(good.replace(OPEN_ON_CLICK_RETURN, "_ = self?.openOnClick()")))
        self.assertFalse(click_open_returns_before_outside(good.replace("self?.openOnClick() == true { return }", "self?.openOnClick() == true { }")))
        self.assertFalse(local_mouse_down_opens_on_click(good.replace("self?.openOnClick()", "self?.noop()")))
        hover = f"{HOVER_GATE} {{ return }}\nguard topBar != nil else {{ show(.panel); return }}\nhoverTask = Task {{ }}"
        self.assertTrue(hover_gate_precedes_the_dwell(hover))
        self.assertFalse(hover_gate_precedes_the_dwell(hover.replace(HOVER_GATE, "guard true else")))
        self.assertFalse(hover_gate_precedes_the_dwell("guard topBar != nil else { show(.panel); return }\n" + HOVER_GATE + " { return }\nhoverTask = Task { }"))
        self.assertTrue(check_precedes("guard Self.enabled else {}\nask(query)", "guard Self.enabled else", "ask(query)"))
        self.assertFalse(check_precedes("ask(query)\nguard Self.enabled else {}", "guard Self.enabled else", "ask(query)"))
        self.assertFalse(check_precedes("ask(query)", "guard Self.enabled else", "ask(query)"))


class Pass3StaleReadWiring(unittest.TestCase):
    def test_launch_at_login_read_is_invalidated_by_a_toggle(self):
        text = pass3_source("Sources/Zeus/App/SettingsStore.swift")
        self.assertIn("launchReads.invalidate()", pass3_function_body(text, "private func applyLaunchAtLogin("))
        self.assertIn("launchReads.isCurrent(read)", text)

    def test_hook_read_is_invalidated_by_connect_and_disconnect(self):
        text = pass3_source("Sources/Zeus/Integrations/AIConnections.swift")
        self.assertGreaterEqual(text.count("hookReads.invalidate()"), 3)
        self.assertIn("hookReads.isCurrent(read)", text)


# Model downloads and launch warm-ups (docs/SECURITY-FIXES-20261111.md): a model download starts only from an
# explicit user button, and the brains are never pinged at launch or wake.
SPEECH_ENGINES_FILE = "Dictation/SpeechEngines.swift"
DOWNLOAD_CALLS = re.compile(r"\bAsrModels\.(?:downloadAndLoad|download)\b|\bWhisperKit\.download\b|\bDiarizerModels\.download\b")


def parakeet_transcribe_body(text):
    start = text.index("func transcribe(samples")
    return text[start:text.index("\n    }\n", start)]


class ModelDownloadConsentLint(unittest.TestCase):
    def test_parakeet_download_is_named_only_in_the_engine_file(self):
        offenders = [f"{p.relative_to(ROOT)}:{n}" for p in swift_files() if str(p.relative_to(APP)) != SPEECH_ENGINES_FILE
                     for n, line in code_lines(p) if re.search(r"\bAsrModels\.(?:downloadAndLoad|download)\b", line)]
        self.assertEqual(offenders, [], "only SpeechEngines.swift may download the Parakeet model")

    def test_download_is_behind_the_explicit_prepare_path(self):
        text = "\n".join(line for _, line in code_lines(APP / SPEECH_ENGINES_FILE))
        self.assertIn("allowDownload: true", text)
        self.assertLess(text.index("if downloading, !allowDownload"), text.index("AsrModels.downloadAndLoad"))
        prepare = text[text.index("func prepare(progress"):text.index("func transcribe(samples")]
        self.assertIn("allowDownload: true", prepare)
        self.assertNotIn("allowDownload: true", parakeet_transcribe_body(text), "transcribe must never download")
        self.assertIn("allowDownload: false", parakeet_transcribe_body(text))

    def test_no_model_download_call_runs_from_launch_or_wake(self):
        for name in ("App/AppDelegate.swift", "App/VoiceTurnController.swift", "Brain/BrainWarmScheduler.swift"):
            text = "\n".join(line for _, line in code_lines(APP / name))
            self.assertIsNone(DOWNLOAD_CALLS.search(text), name)

    def test_launch_and_wake_do_not_warm_the_brains(self):
        voice = "\n".join(line for _, line in code_lines(APP / "App/VoiceTurnController.swift"))
        self.assertNotIn("BrainLaunchWarm", voice)
        self.assertNotIn(".prewarm()", voice)
        self.assertIn("BrainWarmScheduler.shared.talkKeyDown()", voice)
        scheduler = "\n".join(line for _, line in code_lines(APP / "Brain/BrainWarmScheduler.swift"))
        self.assertNotIn("didWakeNotification", scheduler)
        self.assertNotIn("forced", scheduler)

    def test_the_hud_monitor_has_no_constant_fast_timer(self):
        text = "\n".join(line for _, line in code_lines(APP / "TopBar/SystemHUDMonitor.swift"))
        self.assertNotRegex(text, r"Timer\(timeInterval:\s*0\.1")
        self.assertNotIn("repeats: true", text)
        self.assertIn("SystemHUDPollPolicy", text)

    def test_lint_detects_its_failure_shapes(self):
        self.assertTrue(DOWNLOAD_CALLS.search("let m = try await AsrModels.downloadAndLoad(version: v)"))
        self.assertTrue(re.search(r"Timer\(timeInterval:\s*0\.1", "pollTimer = Timer(timeInterval: 0.1, repeats: true) {"))
        sample = "func transcribe(samples: [Float]) async throws -> String {\n        let m = try await loadedManager(progress: nil, allowDownload: true)\n    }\n"
        self.assertIn("allowDownload: true", parakeet_transcribe_body(sample))


class PointingMainActorLint(unittest.TestCase):
    """Pointing: this process's Accessibility calls stay on the main actor, and the held-key overlay never takes the mouse."""
    POINTING = APP / "Pointing"

    def test_probe_ax_calls_stay_on_the_main_actor(self):
        probe = (self.POINTING / "PointingTargetProbe.swift").read_text()
        self.assertRegex(probe, r"@MainActor\s+static func hitTest\(atQuartzPoint")
        self.assertNotRegex(probe, r"nonisolated\s+static func hitTest")

    def test_no_pointing_source_runs_the_hit_test_on_a_detached_task(self):
        for path in self.POINTING.glob("*.swift"):
            match = re.search(r"Task\.detached[^\n]*\n?[^\n]*hitTest", path.read_text())
            self.assertIsNone(match, f"{path.name}: hit test inside Task.detached")

    def test_holding_the_keys_never_captures_the_mouse(self):
        controller = (self.POINTING / "PointingController.swift").read_text()
        self.assertNotIn("show(capturingMouse: true)", controller)
        self.assertIn("show(capturingMouse: false)", controller)


class TilingWiringLint(unittest.TestCase):
    """Tiling is off until the owner turns it on, never prompts, never ticks, and its panels are in every hand-kept list."""
    DELEGATE = (APP / "App/AppDelegate.swift").read_text()

    @staticmethod
    def body(text, start, end):
        first = text.index(start)
        return text[first:text.index(end, first)]

    def tiling_sources(self):
        return sorted(TILING.rglob("*.swift")) + [APP / "TopBar/TilingPage.swift"]

    def test_the_controller_starts_only_from_the_gated_sync_and_stops_at_quit(self):
        self.assertIn("if on(.tiling)", self.DELEGATE)
        self.assertEqual(self.DELEGATE.count("TilingController.shared.start()"), 1)
        sync = self.body(self.DELEGATE, "private func syncTiling()", "\n    }\n")
        self.assertIn("guard on(.tiling)", sync)
        self.assertIn("TilingController.shared.start()", sync)
        self.assertIn("UserDefaults.didChangeNotification", self.body(self.DELEGATE, "if on(.tiling) {\n", "\n        }\n"))
        terminate = self.body(self.DELEGATE, "func applicationWillTerminate", "func applicationDidFinishLaunching")
        self.assertIn("TilingController.shared.stop()", terminate)

    def test_quitting_stops_tiling_only_when_the_startup_service_is_allowed(self):
        terminate = self.body(self.DELEGATE, "func applicationWillTerminate", "func applicationDidFinishLaunching")
        self.assertRegex(terminate, r"if on\(\.tiling\) \{\s*TilingController\.shared\.stop\(\)\s*\}")

    def test_the_driver_never_reads_zeus_itself_and_every_driver_must_say_what_is_in_front(self):
        ax = (TILING / "AXTilingWindowDriver.swift").read_text()
        front = self.body(ax, "func frontmost()", "\n    }\n")
        self.assertIn("ProcessInfo.processInfo.processIdentifier", front)
        protocol = (ROOT / "Sources/ZeusCore/Tiling/TileWindowDriver.swift").read_text()
        self.assertNotIn("extension TilingWindowDriver", protocol)

    def test_the_page_marks_the_key_pair_by_shape_and_rechecks_accessibility_when_zeus_is_activated(self):
        page = (APP / "TopBar/TilingPage.swift").read_text()
        keys = self.body(page, "private var keysRow", "\n    }\n")
        self.assertIn("checkmark", keys)
        self.assertIn("NSApplication.didBecomeActiveNotification", page)

    def test_both_overlays_are_in_the_sharing_refresh_and_the_debug_capture_boost(self):
        sharing = (APP / "App/ZeusWindowSharing.swift").read_text()
        for name in ("TilingFocusBorder", "TilingKeySheet"):
            self.assertIn(f"{name}.shared.applyScreenSharePolicy(visibleInShare: visible)", sharing)
            self.assertIn(f"{name}.shared.boostCaptureVisibility(for: captureBoost)", self.DELEGATE)

    def test_every_tiling_panel_is_registered_with_the_window_sharing_policy_when_it_is_made(self):
        for name in ("TilingFocusBorder", "TilingKeySheet"):
            text = (TILING / f"{name}.swift").read_text()
            self.assertIn("ZeusWindowSharing.apply(to: panel", text, name)
            self.assertIn("surface: .zeusStandard", text, name)
            self.assertIn("TopBarStyle.isSnapshot", text, name)

    def test_tiling_never_prompts_for_a_permission(self):
        forbidden = re.compile(r"AXIsProcessTrustedWithOptions|kAXTrustedCheckOptionPrompt|requestAccess\(|requestAuthorization|CGRequestListenEventAccess|CGRequestPostEventAccess|CGRequestScreenCaptureAccess")
        for path in self.tiling_sources():
            self.assertIsNone(forbidden.search(path.read_text()), path.name)

    def test_tiling_has_no_ticking_clock_and_no_sleeping_task(self):
        forbidden = re.compile(r"\bTimelineView\b|Timer\.scheduledTimer|\bTask\.sleep\b|\bTickingView\b|\bEdgeLightClock\b")
        for path in self.tiling_sources():
            self.assertIsNone(forbidden.search(path.read_text()), path.name)

    def test_the_page_makes_no_accessibility_or_overlay_call_of_its_own(self):
        page = (APP / "TopBar/TilingPage.swift").read_text()
        for name in ("AXIsProcessTrusted", "AXUIElement", "AccessibilityGate", "TilingFocusBorder", "TilingKeySheet", "NSScreen"):
            self.assertNotIn(name, page)

    def test_the_page_is_routed_from_the_page_switch(self):
        views = (APP / "TopBar/TopBarViews.swift").read_text()
        self.assertIn("case .tiling: TilingPage(topBar: topBar, tiling: topBar.tilingForSnapshot ?? .shared)", views)

    def test_tiling_is_a_startup_service_a_qa_startup_denies(self):
        core = (ROOT / "Sources/ZeusCore/StartupPolicy.swift").read_text()
        self.assertRegex(core, r"\bcase\b[^\n]*\btiling\b")
        self.assertNotRegex(core.split("qaAllowed", 1)[1].split("\n", 1)[0], r"tiling")

    def test_the_lint_notices_a_ticking_clock_and_a_prompt(self):
        ticking = "struct V: View { var body: some View { TimelineView(.animation) { _ in Text(\"x\") } } }"
        self.assertIsNotNone(re.search(r"\bTimelineView\b", ticking))
        prompt = "let ok = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)"
        self.assertIsNotNone(re.search(r"AXIsProcessTrustedWithOptions|kAXTrustedCheckOptionPrompt", prompt))


def mic_read(relative):
    return (APP / relative).read_text()


def mic_body(text, start, end):
    first = text.index(start)
    return text[first:text.index(end, first)]


class MicReleaseTests(unittest.TestCase):
    def test_quitting_restores_the_ducked_output_device(self):
        terminate = mic_body(mic_read("App/AppDelegate.swift"), "func applicationWillTerminate", "func applicationDidFinishLaunching")
        self.assertIn("SystemAudioDucker.end()", terminate)
        ducker = mic_read("Voice/SystemAudioDucker.swift")
        end = mic_body(ducker, "static func end()", "private static func isMuted")
        self.assertIn("duckedDevice", end)
        self.assertNotIn("defaultOutput()", end)

    def test_a_spoken_todo_releases_the_microphone_when_its_page_closes_or_after_a_minute(self):
        self.assertIn(".onDisappear { todo.endVoice() }", mic_read("TopBar/TodoPage.swift"))
        controller = mic_read("TopBar/TodoController.swift")
        self.assertIn("static let voiceLimitSeconds = 60", controller)
        self.assertIn("func endVoice()", controller)

    def test_closing_the_prompter_cancels_a_recording_that_is_still_starting(self):
        window = mic_read("Prompter/PrompterWindow.swift")
        close = mic_body(window, "func close()", "onVisibilityChange()")
        self.assertIn("recorder.cancel()", close)
        recorder = mic_read("Prompter/PrompterRecorder.swift")
        self.assertIn("if cancelRequested {", recorder)
        self.assertIn("func cancel()", recorder)

    def test_scribe_never_withholds_the_microphone_because_another_app_uses_it(self):
        detector = mic_read("Scribe/ScribeMuteDetector.swift")
        coverage = mic_body(detector, "func coverage(start:", "func otherAppUsingMicrophone")
        self.assertNotIn("hasExternalInput", coverage)
        capture = mic_read("Scribe/ScribeLiveCapture.swift")
        self.assertNotIn("microphoneExcludedByCall", capture)
        rebuild = mic_body(capture, "private func micConfigurationChanged()", "// MARK: System audio")
        self.assertIn(".defaultInputChanged", rebuild)



class ScribeMeetingCardTests(unittest.TestCase):
    def test_scribe_meeting_cards_take_the_first_click(self):
        panel = mic_read("Scribe/ScribeMeetingCardPanel.swift")
        host = mic_body(panel, "final class ScribeCardHostingView", "private final class ScribeMeetingCardWindow")
        self.assertIn("override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }", host)
        self.assertIn(".activeAlways", host)
        self.assertIn("ScribeCardHostingView(rootView:", panel)
        self.assertNotIn("NSHostingView(rootView:", panel)
        self.assertFalse((ROOT / "Sources/Zeus/Scribe/ScribeCallPopup.swift").exists())

    def test_scribe_meeting_card_taps_go_through_the_lifecycle(self):
        # The meeting card, heads-up included: the panel leaves only through `render`, the controller draws the
        # machine's card after every event, and the late tap is decided in the core.
        panel = mic_read("Scribe/ScribeMeetingCardPanel.swift")
        self.assertEqual(panel.count("orderOut("), 1)
        render = mic_body(panel, "    func render(_ card: ScribeMeetingCard) {", "    private func view(")
        self.assertIn("window.orderOut(nil)", render)
        self.assertNotIn("func hide(", panel)
        controller = mic_read("Scribe/ScribeAutoStartController.swift")
        send = mic_body(controller, "    private func send(", "    /// Scribe's phase changed.")
        self.assertIn("refresh()", send)
        changed = mic_body(controller, "    private func scribeChanged(", "    private func perform(")
        self.assertIn("refresh()", changed)
        refresh = mic_body(controller, "    private func refresh() {", "    private func render() {")
        self.assertIn("render()", refresh)
        render_card = mic_body(controller, "    private func render() {", "    private static func log(")
        self.assertIn("machine.card(now: clock())", render_card)
        self.assertIn("panel.render(drawn)", render_card)
        core = (ROOT / "Sources/ZeusCore/Scribe/ScribeAutoStart.swift").read_text()
        self.assertIn("case primary(on: ScribeMeetingCard", core)
        late = mic_body(core, "    private mutating func primary(", "    private mutating func cancel(")
        self.assertIn("The offer ended in the same instant", late)

    def test_scribe_meeting_card_taps_are_logged(self):
        # The meeting card's own machine logs each state change once, and the taps that were ignored.
        controller = mic_read("Scribe/ScribeAutoStartController.swift")
        self.assertIn('NSLog("[ZEUS] scribe meeting: %@", line)', controller)
        self.assertIn('FlightRecorder.shared.record("scribe", "meeting state", line)', controller)
        self.assertIn('Self.log("tap ignored"', controller)
        self.assertIn('Self.log("start"', controller)


# Browser media (docs/NOTCH-SOURCES-PLAN.md, A3): a command reaches a tab only through the feed, and nothing here
# listens to or taps audio.
BROWSER_MEDIA_BRIDGE_FILE = "Chrome/ChromeBridge.swift"
BROWSER_MEDIA_FEED_FILE = "Chrome/BrowserMediaFeed.swift"
BROWSER_MEDIA_NEVER = ["Chrome/ChromeActions.swift", "../ZeusCore/ZeusTag.swift", "../ZeusCore/BrowserCommand.swift"]
BROWSER_MEDIA_NEVER_DIRS = ["Intent", "Voice"]
MEDIA_COMMAND_LITERAL = re.compile(r'"media\.command"')
MEDIA_COMMAND_CALL = re.compile(r"ChromeBridge\.mediaCommand\(")
MEDIA_WORDS = re.compile(r'"media\.command"|mediaCommand\(|"media\.state"')
AUDIO_TAP_APIS = re.compile(r"AudioDeviceCreateIOProc|AudioHardwareCreateProcessTap|AudioHardwareCreateAggregateDevice|\.installTap\(")


def code_text(text):
    return "\n".join(line for line in text.splitlines() if not line.strip().startswith("//"))


def media_literal_offenders(sources):
    """`sources` maps a path under Sources/Zeus to its text. The command literal may appear only in the bridge file,
    the call only in the feed, and the never-files and directories must not name either."""
    offenders = []
    for path, text in sources.items():
        body = code_text(text)
        if MEDIA_COMMAND_LITERAL.search(body) and path != BROWSER_MEDIA_BRIDGE_FILE:
            offenders.append(f"{path}: media.command literal")
        if MEDIA_COMMAND_CALL.search(body) and path != BROWSER_MEDIA_FEED_FILE:
            offenders.append(f"{path}: mediaCommand call")
        never = path in BROWSER_MEDIA_NEVER or any(path.startswith(d + "/") for d in BROWSER_MEDIA_NEVER_DIRS)
        if never and MEDIA_WORDS.search(body):
            offenders.append(f"{path}: names a media request")
    return offenders


def audio_tap_offenders(sources):
    return [f"{path}" for path, text in sources.items() if AUDIO_TAP_APIS.search(code_text(text))]


class BrowserMediaLint(unittest.TestCase):
    def sources(self):
        files = {str(p.relative_to(APP)): p.read_text() for p in swift_files()}
        for rel in ["ZeusTag.swift", "BrowserCommand.swift"]:
            files["../ZeusCore/" + rel] = (ROOT / "Sources/ZeusCore" / rel).read_text()
        return files

    def test_the_media_command_goes_out_only_through_the_bridge_and_the_feed(self):
        self.assertEqual(media_literal_offenders(self.sources()), [])

    def test_the_feed_and_bridge_files_exist_and_carry_their_halves(self):
        self.assertTrue(MEDIA_COMMAND_LITERAL.search((APP / BROWSER_MEDIA_BRIDGE_FILE).read_text()))
        self.assertTrue(MEDIA_COMMAND_CALL.search((APP / BROWSER_MEDIA_FEED_FILE).read_text()))

    def test_the_feed_never_starts_the_call_watcher_and_the_watcher_gains_one_property(self):
        feed = code_text((APP / BROWSER_MEDIA_FEED_FILE).read_text())
        self.assertNotIn("ScribeCallWatcher.shared.start", feed)
        self.assertNotIn("ScribeController", feed)
        watcher = (APP / "Scribe/ScribeCallWatcher.swift").read_text()
        self.assertEqual(watcher.count("var browserCallPresent: Bool"), 1)

    def test_the_output_gate_listens_to_properties_and_never_taps_audio(self):
        self.assertEqual(audio_tap_offenders({p.name: p.read_text() for p in (APP / "Chrome").glob("*.swift")}), [])
        gate = code_text((APP / "Chrome/ChromeOutputActivity.swift").read_text())
        self.assertIn("kAudioProcessPropertyIsRunningOutput", gate)
        self.assertIn("kAudioDevicePropertyDeviceIsRunningSomewhere", gate)
        self.assertNotIn("@MainActor final class", gate, "Core Audio calls these blocks off the main actor")
        self.assertNotIn("@MainActor private", gate, "Core Audio calls these blocks off the main actor")

    def test_the_feed_polls_only_what_the_rules_and_the_machine_allow(self):
        feed = code_text((APP / BROWSER_MEDIA_FEED_FILE).read_text())
        self.assertIn("BrowserPollMachine.next(", feed)
        self.assertIn("BrowserMediaRules.usable(", feed)
        self.assertEqual(feed.count('"media.state"'), 0, "the request type lives in ChromeBridge")

    def test_the_media_toggle_is_never_turned_on_by_an_import(self):
        text = (APP / "App/SettingsStore.swift").read_text()
        block = text[text.index("static let neverEnabledByImport"):]
        block = block[:block.index("]")]
        self.assertIn('"music.browserMedia"', block)

    def test_the_media_lint_detects_its_failure_shapes(self):
        ok = {BROWSER_MEDIA_BRIDGE_FILE: 'send("media.command")', BROWSER_MEDIA_FEED_FILE: "ChromeBridge.mediaCommand(a)"}
        self.assertEqual(media_literal_offenders(ok), [])
        self.assertEqual(media_literal_offenders({**ok, "Chrome/Other.swift": 'let t = "media.command"'}), ["Chrome/Other.swift: media.command literal"])
        self.assertEqual(media_literal_offenders({**ok, "TopBar/X.swift": "ChromeBridge.mediaCommand(a)"}), ["TopBar/X.swift: mediaCommand call"])
        self.assertEqual(media_literal_offenders({**ok, "Voice/Say.swift": "ChromeBridge.mediaCommand(a)"}),
                         ["Voice/Say.swift: mediaCommand call", "Voice/Say.swift: names a media request"])
        self.assertEqual(media_literal_offenders({**ok, "Intent/Go.swift": 'let t = "media.state"'}), ["Intent/Go.swift: names a media request"])
        self.assertEqual(media_literal_offenders({**ok, "Chrome/ChromeActions.swift": 'x = "media.command"'}),
                         ["Chrome/ChromeActions.swift: media.command literal", "Chrome/ChromeActions.swift: names a media request"])
        self.assertEqual(media_literal_offenders({**ok, "../ZeusCore/ZeusTag.swift": "mediaCommand(x)"}), ["../ZeusCore/ZeusTag.swift: names a media request"])
        self.assertEqual(media_literal_offenders({**ok, "Chrome/Other.swift": '// "media.command" in a comment'}), [])
        self.assertEqual(audio_tap_offenders({"a.swift": "AudioHardwareCreateProcessTap(d, &t)"}), ["a.swift"])
        self.assertEqual(audio_tap_offenders({"a.swift": "// AudioDeviceCreateIOProcID"}), [])


# --- Face presence (docs/FACE-PRESENCE-PLAN.md): presence only, never input, passwords, network or stored images ----
FACE_CARD = APP / "Settings/GSFacePresenceCard.swift"
FACE_FORBIDDEN = re.compile(
    r"CGEvent|post\(tap|IOHIDPost|AXUIElementPostKeyboardEvent|keystroke|password|kSecClassInternetPassword|LAContext"
    r"|SACLockScreenImmediate|ScreenLock\.lock\(\)|URLSession|CGImageDestination|NSBitmapImageRep|pngData|ArcFace",
    re.IGNORECASE)
# Face presence may use only the event-free members of ScreenLock.
FACE_LOCK_CALL = re.compile(r"\bScreenLock\.(?!lockWithoutEvents\b|canLockWithoutEvents\b)\w+")


def face_presence_files():
    files = sorted(SOURCES.glob("*/FacePresence/**/*.swift"))
    return files + ([FACE_CARD] if FACE_CARD.exists() else [])


def face_code(text):
    """(line number, code part) for every line of a Swift text, with comments removed."""
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip().startswith("//"):
            yield number, strip_trailing_comment(line)


def face_presence_offenders(text, label="sample", pattern=FACE_FORBIDDEN):
    return [f"{label}:{n}" for n, code in face_code(text) if pattern.search(code)]


class FacePresenceLint(unittest.TestCase):
    def test_face_presence_never_posts_events_or_touches_passwords(self):
        offenders = [o for p in face_presence_files() for o in face_presence_offenders(p.read_text(), str(p.relative_to(ROOT)))]
        self.assertEqual(offenders, [], "face presence must never post events, read passwords, use the network or write images")

    def test_face_presence_locks_only_through_the_event_free_call(self):
        actions = (APP / "Intent/FastActions.swift").read_text()
        enum = actions[actions.index("enum ScreenLock {"):]
        self.assertIn("static var canLockWithoutEvents: Bool { lockFunction != nil }", enum)
        free = "\n".join(code for _, code in face_code(enum[enum.index("static func lockWithoutEvents()"):enum.index("static func lock() -> Bool")]))
        self.assertIn("SACLockScreenImmediate", enum)
        self.assertNotRegex(free, r"CGEvent|AXIsProcessTrusted|\.post\(")
        self.assertIn("guard let function else { return false }", free)
        # lock() keeps its shortcut fallback for the voice intent; the event-free call must stay a separate path.
        self.assertIn("event?.post(tap: .cghidEventTap)", enum[enum.index("static func lock() -> Bool"):])
        offenders = [o for p in face_presence_files() for o in face_presence_offenders(p.read_text(), str(p.relative_to(ROOT)), FACE_LOCK_CALL)]
        self.assertEqual(offenders, [], "face presence may call only lockWithoutEvents and canLockWithoutEvents")
        elsewhere = [f"{p.relative_to(ROOT)}:{n}" for p in sorted(SOURCES.rglob("*.swift")) if p != APP / "Intent/FastActions.swift"
                     for n, code in face_code(p.read_text()) if "SACLockScreenImmediate" in code]
        self.assertEqual(elsewhere, [], "SACLockScreenImmediate is reached only through ScreenLock")

    def test_face_presence_lint_detects_its_failure_shapes(self):
        # Fail-first samples: each banned shape must be flagged, and comments must stay free.
        for shape in ("let e = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)", "event.post(tap: .cghidEventTap)",
                      "IOHIDPostEvent(port, 0, data, 0, 0, 0)", "AXUIElementPostKeyboardEvent(app, 0, 12, true)",
                      "typeKeystroke(\"a\")", "let secret = loginPassword", "kSecClassInternetPassword", "let context = LAContext()",
                      "SACLockScreenImmediate()", "_ = ScreenLock.lock()", "URLSession.shared.dataTask(with: url)",
                      "CGImageDestinationCreateWithURL(url, type, 1, nil)", "NSBitmapImageRep(cgImage: image)", "image.pngData()",
                      "let model = ArcFaceEmbedder()"):
            self.assertEqual(face_presence_offenders(shape), ["sample:1"], shape)
        clean = "// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): FaceDetector.swift.\nlet x = 1 // never a password\n_ = ScreenLock.lockWithoutEvents()"
        self.assertEqual(face_presence_offenders(clean), [])
        self.assertEqual(face_presence_offenders("let s = \"// password\""), ["sample:1"])
        self.assertEqual(face_presence_offenders("a\nb\nimage.pngData()"), ["sample:3"])
        self.assertEqual(face_presence_offenders("_ = ScreenLock.lock()", pattern=FACE_LOCK_CALL), ["sample:1"])
        self.assertEqual(face_presence_offenders("_ = ScreenLock.canLockWithoutEvents", pattern=FACE_LOCK_CALL), [])
        self.assertEqual(face_presence_offenders("_ = ScreenLock.lockWithoutEvents()", pattern=FACE_LOCK_CALL), [])
        self.assertEqual(face_presence_offenders("_ = ScreenLock.lockWithoutEventsAnyway()", pattern=FACE_LOCK_CALL), ["sample:1"])


# --- Per-app equaliser (docs/NOTCH-EQUALISER-PLAN.md, ticket B2b) --------------------------------------------
# The render callback runs on a realtime thread; the lints below keep it free of allocation and main-actor hops,
# keep IOProc blocks in audited files, keep every Core Audio listener block in a nonisolated function, and keep
# real taps out of tests.
EQ_DIR = APP / "Audio/Equaliser"
EQ_SHAPING_TAP = EQ_DIR / "AppShapingTap.swift"
EQ_MONITOR = EQ_DIR / "AudioProcessMonitor.swift"
EQ_KERNEL = ROOT / "Sources/ZeusCore/Audio/EqualiserDSP.swift"
EQ_RENDER_START = "// MARK: - Render (realtime)"
EQ_RENDER_END = "// MARK: - End of render"
KERNEL_CLASS_HEADER = "public final class EqualiserKernel"
KERNEL_PROCESS_HEADER = "    public func process("
IO_PROC_API = re.compile(r"\bAudioDeviceCreateIOProcID(?:WithBlock)?\b")
AUDITED_IO_PROC_FILES = {"Audio/SystemAudioTap.swift", "Scribe/ScribeLiveCapture.swift", "Audio/Equaliser/AppShapingTap.swift"}
# Nothing on the render path may allocate, lock, log or reach the main actor or Swift concurrency.
RENDER_FORBIDDEN = re.compile(
    r"\.append\(|\bArray\(|\bString\(|\bDispatchQueue\b|\bMainActor\b|\bprint\(|\bNSLog\(|\bos_log\b"
    r"|\bTask\s*[{(.]|\bawait\b|\bNSLock\b|\.lock\(\)|\.withLock\b"
    r"|(?:[=(,:]|\breturn\b|\bin\b)\s*\[|\]\s*\(")
# Names that open a tap, a live monitor or the System Audio Recording prompt. Tests use fakes and pure rules.
TAP_CREATION_NAMES = re.compile(
    r"AudioHardwareCreateProcessTap|AudioHardwareCreateAggregateDevice|CATapDescription|LiveShapingTapFactory"
    r"|AudioProcessMonitor\(|AppShapingTap\.build\(|\bSystemAudioTap\b|\bSpectrumPipeline\b|\bAudioSpectrumService\b"
    r"|\bScribeLiveCaptureProvider\b")
LIVE_PORT_CONSTRUCTORS = re.compile(r"\b(?:LiveShapingTapFactory|AudioProcessMonitor)\(")
EQ_CONTROLLER = EQ_DIR / "EqualiserController.swift"
APP_DELEGATE = APP / "App/AppDelegate.swift"
PORT_NAMES = ("factory", "monitor", "claim", "scheduler")
EQ_LISTENER_APIS = re.compile(r"AudioObjectAddPropertyListenerBlock|AudioObjectRemovePropertyListenerBlock")
DASHES = ("—", "–")


def render_offenders(text, label="sample"):
    """`label:line` for each forbidden construct in the code part of `text`."""
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        code = strip_trailing_comment(line)
        if code.strip().startswith("//"):
            continue
        if RENDER_FORBIDDEN.search(code):
            found.append(f"{label}:{number}")
    return found


def live_port_offenders(text, label="sample"):
    """`label:line` for each line that builds a live tap factory or process monitor."""
    return [f"{label}:{n}" for n, line in enumerate(text.splitlines(), 1)
            if not line.strip().startswith("//") and LIVE_PORT_CONSTRUCTORS.search(strip_trailing_comment(line))]


def port_default_offenders(signature):
    """Port parameters in an initializer signature that carry a default value."""
    return [port for port in PORT_NAMES
            if re.search(rf"^\s*{port}:[^\n]*=", signature, re.MULTILINE)]


def io_proc_offenders(text, label="sample"):
    return [f"{label}:{n}" for n, line in enumerate(text.splitlines(), 1)
            if not line.strip().startswith("//") and IO_PROC_API.search(strip_trailing_comment(line))]


def listener_offenders(text, label="sample"):
    """Core Audio listener calls outside a function declared `nonisolated`."""
    lines = text.splitlines()
    offenders = []
    for index, line in enumerate(lines):
        if line.strip().startswith("//") or not EQ_LISTENER_APIS.search(strip_trailing_comment(line)):
            continue
        header = next((lines[i] for i in range(index, -1, -1) if re.search(r"\bfunc\b", lines[i])), "")
        if "nonisolated" not in header:
            offenders.append(f"{label}:{index + 1}")
    return offenders


def between(text, start, end=None):
    first = text.index(start)
    return text[first:text.index(end, first)] if end else text[first:]


class EqualiserLint(unittest.TestCase):
    def test_io_proc_blocks_only_in_audited_files(self):
        offenders = []
        for path in swift_files():
            if path.relative_to(APP).as_posix() not in AUDITED_IO_PROC_FILES:
                offenders += io_proc_offenders(path.read_text(), path.relative_to(ROOT).as_posix())
        self.assertEqual(offenders, [], "an IOProc block belongs in an audited non-main-actor file")

    def test_shaping_render_has_no_allocation_or_main_hops(self):
        render = between(EQ_SHAPING_TAP.read_text(), EQ_RENDER_START, EQ_RENDER_END)
        self.assertRegex(render, r"nonisolated static func makeRenderBlock\(\s*kernel:")
        self.assertIn("kernel.process(", render)
        kernel = between(between(EQ_KERNEL.read_text(), KERNEL_CLASS_HEADER), KERNEL_PROCESS_HEADER)
        self.assertIn("private func processChunk(", kernel)
        offenders = render_offenders(render, "AppShapingTap.swift") + render_offenders(kernel, "EqualiserDSP.swift")
        self.assertEqual(offenders, [], "no allocation, lock, log or main-actor hop on the render path")

    def test_the_io_proc_block_is_built_by_the_nonisolated_render_function(self):
        text = EQ_SHAPING_TAP.read_text()
        self.assertEqual(len(re.findall(r"AudioDeviceCreateIOProcIDWithBlock\(", text)), 1)
        self.assertIn("AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue, block)", text)
        self.assertIn("block = Self.makeRenderBlock(", text)
        self.assertIn("block = Self.makeProbeBlock(", text)
        self.assertRegex(text, r"nonisolated static func makeProbeBlock\(")

    def test_core_audio_listeners_are_installed_from_nonisolated_functions(self):
        text = EQ_MONITOR.read_text()
        self.assertTrue(EQ_LISTENER_APIS.search(text))
        self.assertEqual(listener_offenders(text, "AudioProcessMonitor.swift"), [])

    def test_tests_never_create_a_tap(self):
        offenders = []
        for path in sorted((ROOT / "Tests").rglob("*.swift")):
            offenders += [f"{path.relative_to(ROOT)}:{n}" for n, line in code_lines(path)
                          if TAP_CREATION_NAMES.search(strip_trailing_comment(line))]
        self.assertEqual(offenders, [], "tests use fakes; a real tap or monitor raises the system audio prompt")

    def test_live_audio_ports_are_built_only_by_the_app_delegate(self):
        offenders = []
        for path in swift_files():
            relative = path.relative_to(APP).as_posix()
            if relative != "App/AppDelegate.swift":
                offenders += live_port_offenders(path.read_text(), relative)
        self.assertEqual(offenders, [], "a test reaches Sources through the module, so only the launch builds live ports")
        launch = between(APP_DELEGATE.read_text(), "private func makeEqualiser()", "equaliser = controller")
        self.assertEqual(len(live_port_offenders(launch, "AppDelegate.swift")), 2)

    def test_the_controller_takes_its_audio_ports_without_defaults(self):
        signature = between(EQ_CONTROLLER.read_text(), "    init(\n", "    ) {")
        for port in PORT_NAMES:
            self.assertRegex(signature, rf"\n\s+{port}: ", port)
        self.assertEqual(port_default_offenders(signature), [], "a test that forgets a port must not get a live one")

    def test_prompt_lints_detect_their_failure_shapes(self):
        for shape in ("let t = SystemAudioTap()", "let p = SpectrumPipeline()", "AudioSpectrumService.shared.allowPressed()",
                      "ScribeLiveCaptureProvider(monitor: m)", "try AppShapingTap.build(request, mode: .probe)",
                      "AudioHardwareCreateAggregateDevice(d, &id)"):
            self.assertTrue(TAP_CREATION_NAMES.search(shape), shape)
        for quiet in ("AppShapingTap.makeRenderBlock(kernel: k)", "let m = FakeMonitor()", "SpectrumMath.gain(sensitivityPercent: 50)"):
            self.assertFalse(TAP_CREATION_NAMES.search(quiet), quiet)
        self.assertEqual(live_port_offenders("let f = LiveShapingTapFactory()", "s"), ["s:1"])
        self.assertEqual(live_port_offenders("monitor: AudioProcessMonitor(),", "s"), ["s:1"])
        self.assertEqual(live_port_offenders("// AudioProcessMonitor() is built at launch", "s"), [])
        self.assertEqual(live_port_offenders("final class AudioProcessMonitor: EqualiserMonitoring {", "s"), [])
        self.assertEqual(port_default_offenders("    init(\n        factory: any ShapingTapFactory = LiveShapingTapFactory(),\n"), ["factory"])
        self.assertEqual(port_default_offenders("        monitor: any EqualiserMonitoring,\n        claim: any EqualiserClaiming,\n"), [])

    def test_device_pickers_never_offer_a_zeus_aggregate(self):
        for relative in ("TopBar/OutputDevices.swift", "Dictation/Microphones.swift"):
            text = "\n".join(line for _, line in code_lines(APP / relative))
            self.assertIn("ZeusAudioDevices.isOwnAggregate(", text, relative)

    def test_equaliser_files_carry_no_dash(self):
        paths = sorted(EQ_DIR.glob("*.swift")) + sorted((ROOT / "Sources/ZeusCore/Audio").glob("Equaliser*.swift"))
        paths += sorted((ROOT / "Tests").rglob("Equaliser*.swift"))
        self.assertTrue(paths)
        offenders = [f"{p.relative_to(ROOT)}:{n}" for p in paths
                     for n, line in enumerate(p.read_text().splitlines(), 1) if any(d in line for d in DASHES)]
        self.assertEqual(offenders, [])

    def test_equaliser_lints_detect_their_failure_shapes(self):
        # Fail-first samples: the exact shapes each lint exists to catch.
        self.assertEqual(render_offenders("scratch.append(sample)", "s"), ["s:1"])
        self.assertEqual(render_offenders("let copy = Array(buffer)", "s"), ["s:1"])
        self.assertEqual(render_offenders("let name = String(count)", "s"), ["s:1"])
        self.assertEqual(render_offenders("let order = [0, 1]", "s"), ["s:1"])
        self.assertEqual(render_offenders("let silent = [Float](repeating: 0, count: n)", "s"), ["s:1"])
        self.assertEqual(render_offenders("DispatchQueue.main.async { tick() }", "s"), ["s:1"])
        self.assertEqual(render_offenders("MainActor.assumeIsolated { tick() }", "s"), ["s:1"])
        self.assertEqual(render_offenders("print(frames)", "s"), ["s:1"])
        self.assertEqual(render_offenders('NSLog("late")', "s"), ["s:1"])
        self.assertEqual(render_offenders("Task { await tick() }", "s"), ["s:1"])
        self.assertEqual(render_offenders("lock.lock()", "s"), ["s:1"])
        self.assertEqual(render_offenders("samples[frame * channels + channel] = 0", "s"), [])
        self.assertEqual(render_offenders("kinds[band], frequency: frequencies[band],", "s"), [])
        self.assertEqual(render_offenders("// scratch.append(sample) is forbidden here", "s"), [])
        self.assertEqual(io_proc_offenders("AudioDeviceCreateIOProcIDWithBlock(&id, device, queue) { }", "s"), ["s:1"])
        self.assertEqual(io_proc_offenders("// AudioDeviceCreateIOProcIDWithBlock is audited", "s"), [])
        bad = "@MainActor final class A {\n    func start() {\n        AudioObjectAddPropertyListenerBlock(o, &a, q) { _, _ in }\n    }\n}"
        self.assertEqual(listener_offenders(bad), ["sample:3"])
        good = "enum B {\n    nonisolated static func start() {\n        AudioObjectAddPropertyListenerBlock(o, &a, q) { _, _ in }\n    }\n}"
        self.assertEqual(listener_offenders(good), [])
        self.assertTrue(TAP_CREATION_NAMES.search("let t = CATapDescription(stereoMixdownOfProcesses: [])"))
        self.assertTrue(TAP_CREATION_NAMES.search("_ = AudioHardwareCreateProcessTap(d, &id)"))
        self.assertTrue(TAP_CREATION_NAMES.search("let f = LiveShapingTapFactory()"))
        self.assertTrue(TAP_CREATION_NAMES.search("let m = AudioProcessMonitor()"))
        self.assertFalse(TAP_CREATION_NAMES.search("let m = FakeMonitor()"))


class TalkChordOrderLint(unittest.TestCase):
    """The talk chord's Carbon key (ZTLK) holds Control-Option-Space until the chord has been synced. A Carbon shortcut
    registered before that sync fails silently while it holds, so the sync comes first where both run together."""

    def test_the_chord_is_synced_before_the_shortcuts_are_registered(self):
        lines = [line for _, line in code_lines(APP / "App/AppDelegate.swift")]
        pairs = 0
        for index, line in enumerate(lines):
            if "registerShortcuts()" not in line or "func registerShortcuts" in line:
                continue
            nearby = lines[max(0, index - 3):index + 4]
            if not any("syncTalkChord()" in other for other in nearby):
                continue
            pairs += 1
            before = lines[max(0, index - 3):index]
            self.assertTrue(any("syncTalkChord()" in other for other in before),
                            f"syncTalkChord() must run before registerShortcuts(): {line.strip()}")
        self.assertGreaterEqual(pairs, 1, "the shortcut change handler runs both")


if __name__ == "__main__":
    unittest.main()
