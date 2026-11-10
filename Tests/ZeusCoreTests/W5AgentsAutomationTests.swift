import Foundation
import Testing
import ZeusCore

@Suite("W5 agents and automation")
struct W5AgentsAutomationTests {
    // MARK: zeus listen --seconds

    @Test func listenSecondsRefusesNonFiniteAndHugeValues() {
        for value in ["inf", "1e999", "9.3e18", "3601"] {
            #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["listen", "--seconds", value]) }
        }
    }

    @Test func listenSecondsAcceptsNormalValues() throws {
        let invocation = try ZeusCLI.parse(["listen", "--seconds", "30"])
        #expect(invocation.command?.seconds == 30)
        let longest = try ZeusCLI.parse(["listen", "--seconds", "3600"])
        #expect(longest.command?.seconds == 3600)
    }

    // MARK: Memory and the meetings folder

    @Test func missingOrEmptyMeetingsNeverCountAsDeleted() {
        #expect(!WikiCompiler.mayRemoveMissing(recordCount: 0, failureCount: 0, folderExists: true))
        #expect(!WikiCompiler.mayRemoveMissing(recordCount: 0, failureCount: 0, folderExists: false))
        #expect(!WikiCompiler.mayRemoveMissing(recordCount: 3, failureCount: 0, folderExists: false))
        #expect(!WikiCompiler.mayRemoveMissing(recordCount: 3, failureCount: 1, folderExists: true))
        #expect(WikiCompiler.mayRemoveMissing(recordCount: 3, failureCount: 0, folderExists: true))
    }

    // MARK: Routines file

    @Test func unreadableRoutinesFileIsSetAsideNotOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-routines-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("routines.json")
        let store = RoutineStore(url: url)

        #expect(store.loadChecked().unreadable == false)

        try Data("{ not json".utf8).write(to: url)
        #expect(store.loadChecked().unreadable)

        let kept = try store.setAsideUnreadable()
        #expect(kept.lastPathComponent.hasPrefix("routines.json.bad-"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let keptText = String(decoding: try Data(contentsOf: kept), as: UTF8.self)
        #expect(keptText == "{ not json")
        #expect(store.loadChecked().unreadable == false)
    }

    @Test func savedRoutinesLoadBackAsReadable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-routines-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RoutineStore(url: folder.appendingPathComponent("routines.json"))
        let routine = Routine(name: "Morning", prompt: "Summarise my day", schedule: RoutineSchedule(days: .weekdays, hour: 9, minute: 0))
        try store.save(.init(routines: [routine], runs: []))
        let loaded = store.loadChecked()
        #expect(!loaded.unreadable)
        #expect(loaded.contents.routines.map(\.name) == ["Morning"])
    }

    // MARK: Watches

    @Test func windowGoneWaitsWhileTheAppIsStillRunning() {
        let watch = ZeusWatch(label: "Preview", trigger: .windowGone(titleContains: "Preview"))
        let running = FakeMacSnapshot(frontApp: "Xcode", frontWindowTitle: "", openTitles: ["Xcode", "Preview"])
        #expect(!ZeusWatchEvaluator.evaluate(watch, mac: running).fired)
        let quit = FakeMacSnapshot(frontApp: "Xcode", frontWindowTitle: "", openTitles: ["Xcode"])
        #expect(ZeusWatchEvaluator.evaluate(watch, mac: quit).fired)
    }

    @Test func windowShowsMatchesARunningApp() {
        let watch = ZeusWatch(label: "Xcode", trigger: .windowShows(titleContains: "Xcode"))
        #expect(!ZeusWatchEvaluator.evaluate(watch, mac: FakeMacSnapshot(frontApp: "Finder", openTitles: ["Finder"])).fired)
        #expect(ZeusWatchEvaluator.evaluate(watch, mac: FakeMacSnapshot(frontApp: "Finder", openTitles: ["Finder", "Xcode"])).fired)
    }

    @Test func buildPhraseUsesTheOneRunnableTest() {
        let watch = ZeusWatchVoice.parse("when the build finishes")
        #expect(watch?.trigger == .shellTest(exitZeroWhen: ZeusWatchVoice.buildFinishedTest))
        #expect(ZeusWatchVoice.isRunnableTest(ZeusWatchVoice.buildFinishedTest))
        #expect(!ZeusWatchVoice.isRunnableTest("rm -rf /tmp/x"))
    }
}
