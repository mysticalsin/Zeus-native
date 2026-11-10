import Foundation
import Testing
@testable import ZeusCore

@Suite("User memory")
struct UserMemoryTests {
    @Test func rememberAndPrompt() {
        var store = UserMemoryStore()
        guard case .storedRule = store.rememberRule("I prefer metric units") else {
            Issue.record("expected stored rule")
            return
        }
        #expect(store.promptBlock(for: "distance to Paris").localizedCaseInsensitiveContains("metric"))
    }

    @Test func forgetRemovesRule() {
        var store = UserMemoryStore()
        _ = store.rememberRule("I prefer tea")
        #expect(store.forget(matching: "tea") == 1)
        #expect(store.rules.isEmpty)
    }

    @Test func blocksSensitiveAndScreen() {
        var store = UserMemoryStore()
        #expect(store.learnFromScreen("4111 1111 1111 1111") == .rejectedScreenSource)
        #expect(store.rememberFact("password is secret") == .rejectedSensitive)
    }

    @Test func commandParse() {
        #expect(UserMemoryCommands.parse("remember I like jazz")?.kind == .remember("I like jazz"))
        #expect(UserMemoryCommands.parse("forget that")?.kind == .forget("that"))
    }
}

@Suite("Zeus watch")
struct ZeusWatchTests {
    @Test func shellWatchFires() {
        let watch = ZeusWatch(label: "build", trigger: .shellTest(exitZeroWhen: "test -f done"))
        let mac = FakeMacSnapshot(shellTests: ["test -f done": true])
        #expect(ZeusWatchEvaluator.evaluate(watch, mac: mac).fired)
    }

    @Test func noLLMWhilePolling() {
        var llm = 0
        let watch = ZeusWatch(label: "title", trigger: .windowGone(titleContains: "Build"))
        let states = [FakeMacSnapshot(frontWindowTitle: "Build"), FakeMacSnapshot(frontWindowTitle: "Done")]
        let (fired, _) = ZeusWatchEvaluator.pollUntilFire(watch: watch, macStates: states, llmCalls: &llm)
        #expect(fired)
        #expect(llm == 0)
    }
}

@Suite("Routine launchd")
struct RoutineLaunchdTests {
    @Test func voiceDefaultEngineIsRouterChoiceNotBareOllama() {
        #expect(Routine.voiceDefaultEngine == .engine(.ollama))
        if case .engine(let engine) = Routine.voiceDefaultEngine {
            #expect(engine == .ollama)
        } else {
            Issue.record("voice routines must pin a local engine")
        }
    }

    @Test func plistHasCalendarInterval() {
        let routine = Routine(name: "Brief", prompt: "p", schedule: .init(days: .weekdays, hour: 8, minute: 0), created: Date())
        let plist = RoutineLaunchAgent.plist(routine: routine, zeusBinary: "/tmp/zeus")
        #expect(plist["StartCalendarInterval"] != nil)
    }

    @Test func relaunchGuardBlocksDuplicateSlot() {
        var guardState = RoutineRelaunchGuard()
        let routine = Routine(name: "Brief", prompt: "p", created: Date())
        let slot = Date(timeIntervalSince1970: 1_700_000_000)
        let first = guardState.shouldRun(routine: routine, scheduled: slot)
        #expect(first)
        guardState.markRan(routineID: routine.id, scheduled: slot)
        let second = guardState.shouldRun(routine: routine, scheduled: slot)
        #expect(!second)
    }
}

@Suite("Background agents")
struct BackgroundAgentTests {
    @Test func moveAfterFifteenSeconds() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(!BackgroundAgentCoordinator.shouldMoveToBackground(started: start, now: Date(timeIntervalSince1970: 10)))
        #expect(BackgroundAgentCoordinator.shouldMoveToBackground(started: start, now: Date(timeIntervalSince1970: 16)))
    }

    @Test func steerKeepsSession() {
        var session = BackgroundAgentSession(title: "Hub")
        let id = session.id
        session.steer("check HDMI")
        #expect(session.id == id)
        #expect(session.steerMessages == ["check HDMI"])
    }
}

@Suite("Meeting copilot")
struct MeetingCopilotTests {
    @Test func fixtureTranscript() throws {
        guard let url = Bundle.module.url(forResource: "meeting-call", withExtension: "txt", subdirectory: "Fixtures") else {
            Issue.record("missing fixture")
            return
        }
        let transcript = try MeetingCopilotEngine.transcribeFixture(at: url)
        #expect(transcript.lines.count >= 2)
        let answer = transcript.answer(question: "What did they say about budget?")
        #expect(answer.localizedCaseInsensitiveContains("budget"))
    }

    @Test func archiveIs0600() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-meeting-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = MeetingArchive(url: dir.appendingPathComponent("events.jsonl"))
        try archive.append(.init(date: Date(), kind: "note", detail: "x"))
        let mode = (try FileManager.default.attributesOfItem(atPath: archive.url.path)[.posixPermissions] as? NSNumber)?.uint16Value
        #expect(mode == 0o600)
    }
}

@Suite("Silent eval harness")
struct SilentEvalHarnessTests {
    @Test func atLeastFifteenScenariosPass() {
        let report = SilentEvalHarness.runAll()
        #expect(report.scenarios.count >= SilentEvalHarness.minimumScenarios)
        #expect(report.pass)
    }
}
