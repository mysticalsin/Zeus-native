import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The offline voice harness over a WAV made with macOS's own `say` (no model download). The
/// recogniser stage needs Speech Recognition access, which a test run doesn't have, so the
/// transcript is supplied and the other stages (file, activity, wake split, routing) run for real.
@Suite("Voice self-test")
struct VoiceSelfTestTests {
    @MainActor @Test func wavThroughTheStages() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zeus.voice.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let wav = dir.appendingPathComponent("hey-zeus.wav")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", wav.path, "--file-format=WAVE", "--data-format=LEI16@16000", "Hey Zeus, what time is it"]
        say.standardError = FileHandle.nullDevice
        guard (try? say.run()) != nil else { return }
        say.waitUntilExit()
        guard say.terminationStatus == 0, FileManager.default.fileExists(atPath: wav.path) else { return } // no voice installed: nothing to test

        setenv("ZEUS_LOG_DIR", dir.path, 1)
        let code = await VoiceSelfTest.run(wav: wav, transcript: "Hey Zeus, what time is it", speak: false)
        #expect(code == 0)
        let missing = await VoiceSelfTest.run(wav: dir.appendingPathComponent("nope.wav"), transcript: nil, speak: false)
        #expect(missing == 2)
    }

    /// Item 6, QA7: QA's own repro used `say -v Daniel` (a non-default voice) through the
    /// speakers, which exercises the same WAV-through-the-stages path with a different accent.
    @MainActor @Test func danielVoiceWavThroughTheStages() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zeus.voice.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let wav = dir.appendingPathComponent("hey-zeus-daniel.wav")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Daniel", "-o", wav.path, "--file-format=WAVE", "--data-format=LEI16@16000", "Hey Zeus, open notes"]
        say.standardError = FileHandle.nullDevice
        guard (try? say.run()) != nil else { return }
        say.waitUntilExit()
        guard say.terminationStatus == 0, FileManager.default.fileExists(atPath: wav.path) else { return } // Daniel not installed: nothing to test

        setenv("ZEUS_LOG_DIR", dir.path, 1)
        let code = await VoiceSelfTest.run(wav: wav, transcript: "Hey Zeus, open notes", speak: false)
        #expect(code == 0)
    }
}

@Suite("Wake request cleanup and quota fallback")
struct WakeCleanupTests {
    @Test func wakeEchoesAreDroppedFromTheFront() {
        #expect(VoiceTurnController.dropWakeEchoes("Siri open calculator") == "open calculator")
        #expect(VoiceTurnController.dropWakeEchoes("hey Zoos, open Spotify") == "open Spotify")
        #expect(VoiceTurnController.dropWakeEchoes("open Siri settings") == "open Siri settings")
        #expect(VoiceTurnController.dropWakeEchoes("Siri") == "Siri")
    }

    @Test func quotaErrorsAreRecognised() {
        #expect(RouterSettings.isQuotaError("You've hit your weekly limit · resets Nov 6 at 4pm"))
        #expect(RouterSettings.isQuotaError("Error 429: rate limit exceeded"))
        #expect(!RouterSettings.isQuotaError("Not logged in"))
    }
}

@Suite("QA round 1 fixes")
struct QARoundOneTests {
    @Test func repeatedWordsCollapse() {
        #expect(VoiceTurnController.dropWakeEchoes("open open calculator") == "open calculator")
        #expect(VoiceTurnController.dropWakeEchoes("Siri open open Notes") == "open Notes")
    }

    @Test func cliErrorLineSkipsTheBanner() {
        let stderr = """
        Reading additional input from stdin...
        OpenAI Codex v0.166.0
        --------
        workdir: /tmp/x
        model: gpt-6-luna
        user
        Reply with just: ok
        warning: Code Mode is unavailable
        ERROR: You’ve hit your usage limit. Try again at Nov 4th, 2026 3:38 AM.
        """
        let line = CLIEngineProvider.errorLine(stderr)
        #expect(line.hasPrefix("You’ve hit your usage limit"))
        #expect(RouterSettings.isQuotaError(line))
    }

    @MainActor @Test func quotaErrorsAreSpokenPlainly() {
        struct E: LocalizedError { var errorDescription: String? }
        let spoken = VoiceTurnController.spokenError(E(errorDescription: "Codex: You’ve hit your usage limit."))
        #expect(spoken.contains("out of quota"))
        #expect(!spoken.contains("Claude"))
    }

    /// Item 5, QA7: every spoken error, for every failure kind, is one short sentence (≤10 words),
    /// matching the persona's "no flourish for errors" rule.
    @MainActor @Test func everySpokenErrorKindStaysOneShortSentence() {
        struct E: LocalizedError { var errorDescription: String? }
        let cases: [String] = [
            "Codex: You’ve hit your usage limit.",
            "Claude: not logged in (401).",
            "Can't find the Claude CLI on your PATH; install it with the official instructions.",
            "The network is offline, couldn't connect to the AI provider.",
            "Something unexpected happened deep inside the tool call pipeline.",
        ]
        for description in cases {
            let spoken = VoiceTurnController.spokenError(E(errorDescription: description))
            #expect(spoken.split(separator: " ").count <= 10, "\(spoken)")
            #expect(spoken.filter { ".!?".contains($0) }.count <= 1, "\(spoken)")
        }
    }
}

@Suite("QA round 2 fixes")
struct QARoundTwoTests {
    @Test func signInErrorsAreRecognised() {
        #expect(RouterSettings.isSignInError("Gemini: Please run gemini to authenticate (no auth)"))
        #expect(RouterSettings.isSignInError("Not logged in · Please run /login"))
        #expect(!RouterSettings.isSignInError("You've hit your usage limit"))
    }

    @Test func allEnginesFailingOnQuotaOrSignInSaysSo() {
        let line = VoiceTurnController.allEnginesFailed(["Claude: weekly limit", "Codex: You’ve hit your usage limit", "Gemini: not logged in"])
        #expect(RouterSettings.isQuotaError(line))
    }

    // QA7 round 11 (report-11.md, "Speed" FAIL): CLIEngineProvider's own 30 s silent-timeout
    // ("<engine> gave no answer in time", e.g. observed on Ollama) wasn't recognised as a reason
    // to park an engine, so every single question paid that same 30 s wait again before falling
    // through further. isTimeoutError is what VoiceTurnController checks to park it (briefly, not
    // the 6-hour quota default) after exactly that message.
    @Test func timeoutErrorsAreRecognisedAndDistinctFromQuotaOrSignIn() {
        #expect(RouterSettings.isTimeoutError("Ollama gave no answer in time"))
        #expect(RouterSettings.isTimeoutError("Cursor Agent GAVE NO ANSWER IN TIME"))
        #expect(!RouterSettings.isTimeoutError("You've hit your usage limit"))
        #expect(!RouterSettings.isTimeoutError("Not logged in"))
        #expect(!RouterSettings.isQuotaError("Ollama gave no answer in time"))
        #expect(!RouterSettings.isSignInError("Ollama gave no answer in time"))
    }

    @MainActor @Test func markingExhaustedWithACustomIntervalExpiresOnItsOwnSchedule() {
        let settings = RouterSettings.shared
        settings.markExhausted(.ollama, for: 0.05)
        #expect(settings.exhaustedEngines().contains(.ollama))
        Thread.sleep(forTimeInterval: 0.1)
        #expect(!settings.exhaustedEngines().contains(.ollama))
    }

    @Test func misheardSiriKeepsTheRequest() {
        #expect(WakeWordListener.afterZeus("Hey Siri open Notes") == "open notes")
    }
}
