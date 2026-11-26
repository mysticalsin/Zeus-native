import Testing
@testable import Zeus

@Suite("Step zero session")
struct StepZeroSessionTests {
    @Test @MainActor func runStaysIdleUntilContinue() async {
        let skipped = FinishSection()
        let idle = StepZeroSession(section: skipped, limitSeconds: 5)
        idle.limitElapsed(generation: 1)
        idle.skipPressed()
        #expect(skipped.calls == 0)
        #expect(idle.phase == .skipped)

        let early = FinishSection()
        let waiting = StepZeroSession(section: early, limitSeconds: 5)
        waiting.continuePressed()
        #expect(early.calls == 0)
        waiting.arm()
        #expect(early.calls == 0)
        #expect(waiting.phase == .notRun)
        waiting.continuePressed()
        await until { early.calls == 1 }
        #expect(early.calls == 1)
        #expect(waiting.phase == .running || waiting.phase == .done)

        let blocked = FinishSection()
        let zero = StepZeroSession(section: blocked, limitSeconds: 0)
        zero.arm()
        zero.continuePressed()
        await Task.yield()
        #expect(blocked.calls == 0)
        #expect(zero.generation == nil)
        #expect(StepZeroSession.continueDeadMilliseconds == 1500)
    }

    @Test @MainActor func hangingSectionEndsOnTheLimit() async {
        let section = HangSection()
        let session = StepZeroSession(section: section, limitSeconds: 5)
        session.arm()
        let generation = session.generation
        session.continuePressed()
        await until { section.calls == 1 }
        #expect(session.phase == .running)
        session.limitElapsed(generation: 0)
        #expect(session.phase == .running)
        #expect(session.fire == nil)
        session.limitElapsed(generation: generation ?? -1)
        #expect(session.phase == .stopped)
        #expect(session.fire?.exitCode == StepZeroWatchdog.exitCode)
        #expect(session.fire?.step == .timedOut)
        #expect(session.fire?.closesWindow == false)
        #expect(session.fire?.closesSpace == false)
        #expect(session.fire?.restores == [.listeningMode, .defaultOutput, .stopChild])
        await Task.yield()
        await Task.yield()
        #expect(session.phase == .stopped)
        #expect(section.calls == 1)
    }

    @Test @MainActor func finishedSectionStaysDone() async {
        let section = FinishSection()
        let session = StepZeroSession(section: section, limitSeconds: 5)
        session.arm()
        session.continuePressed()
        await until { section.calls == 1 && session.phase == .done }
        session.continuePressed()
        await Task.yield()
        session.limitElapsed(generation: session.generation ?? -1)
        #expect(section.calls == 1)
        #expect(session.phase == .done)
        #expect(session.fire == nil)
    }

    @Test func everyResultWordResolves() {
        #expect(StepZeroView.Word.allCases.count == 7)
        for word in StepZeroView.Word.allCases {
            #expect(StepZeroView.symbolResolves(word.symbol))
            #expect(StepZeroView.voiceOverLabel(for: word.rawValue) == word.rawValue)
        }
        #expect(StepZeroView.needs == ["Earbuds", "Second display", "Phone"])
        for name in StepZeroView.needs {
            #expect(StepZeroView.symbolResolves(StepZeroView.needSymbol(name) ?? ""))
        }
        #expect(StepZeroView.needSymbol("Song") == nil)
        #expect(StepZeroView.symbolResolves("tagline") == false)
    }

    @Test func hostedViewUsesTheFixedList() {
        let hosted = StepZeroView.hosted(
            words: [.yourTurn, .notRun, .notRun, .notRun, .notRun, .notRun, .notRun],
            line: .lockScreen,
            showNeeds: true,
            owesRestore: true,
            putBackWord: .notRun,
            grantsOn: ["Bluetooth", "Camera"],
            grantsBack: ["Full Disk Access"],
            notPutBack: ["Listening mode", "a free note"],
            digest: "0123456789abcdef"
        )
        #expect(StepZeroView.holdsOnlyFixed(hosted))
        #expect(hosted.prose.contains("Camera") == false)
        #expect(hosted.prose.contains("a free note") == false)
        #expect(hosted.prose.contains(StepZeroView.lockInstruction))
        #expect(hosted.prose.contains(StepZeroView.Sentence.lockScreen.rawValue))
        #expect(hosted.digest == "0123456789abcdef")

        let stray = StepZeroView.Hosted(prose: hosted.prose + ["tagline"], digest: hosted.digest)
        #expect(StepZeroView.holdsOnlyFixed(stray) == false)
        let badDigest = StepZeroView.Hosted(prose: hosted.prose, digest: "not a digest")
        #expect(StepZeroView.holdsOnlyFixed(badDigest) == false)
        let upper = StepZeroView.hosted(
            words: Array(repeating: .notRun, count: 7),
            line: nil,
            showNeeds: false,
            owesRestore: false,
            putBackWord: nil,
            grantsOn: [],
            grantsBack: [],
            notPutBack: [],
            digest: "0123456789ABCDEF"
        )
        #expect(upper.digest == nil)
    }

    @Test func sentencesMatchTheTable() {
        #expect(StepZeroView.Sentence.allCases.map(\.rawValue) == [
            "The last run ended early. This puts your earbuds' listening mode back and stops one helper process.",
            "This reads what any app on this Mac is playing, pauses it, moves the position, and shows the word Zeus in the Mac's own now-playing display for up to three seconds. Each is put back.",
            "This skips to the next track and back in your music player. The player may count one skip.",
            "This puts a small test card on your lock screen while you lock and unlock the Mac. It also asks you to switch user, start the screensaver and sleep the display.",
            "Next, macOS may ask to let ZEUS control Music and Spotify, so the probe can play, pause and skip from the lock screen. The player may count one skip.",
            "This ends the probe on purpose while the test card and the helper are up. You then start it again.",
            "Next, macOS may ask to let ZEUS use Bluetooth. The probe lists the devices paired with this Mac to see whether that needs your permission.",
            "Next, macOS will ask to let ZEUS use Bluetooth, so the probe can see your earbuds connect and read their battery.",
            "This changes your earbuds' listening mode for a few seconds and puts it back.",
            "This reads the two Focus files and keeps yes or no answers only. It asks you to turn a Focus on and off, and to switch Full Disk Access for ZEUS off and on.",
            "This starts a small system tool that tries to list one protected folder, and keeps only whether it could.",
            "This moves the Mac's sound to your earbuds for five seconds and puts it back.",
            "Next, macOS will ask to let ZEUS find devices on your network, so the probe can see how wireless speakers announce themselves.",
            "This watches the notices Music posts while you play, pause, skip and scrub.",
        ])
        for sentence in StepZeroView.Sentence.allCases {
            #expect(StepZeroView.fixed.contains(sentence.rawValue))
        }
    }

    @Test func showReportWaitsForDoneOrSkipped() {
        let notRun = Array(repeating: StepZeroView.Word.notRun, count: 7)
        #expect(StepZeroView.showReportEnabled(notRun, putBack: nil) == false)
        #expect(StepZeroView.showReportEnabled(Array(repeating: .done, count: 7), putBack: nil))
        #expect(StepZeroView.showReportEnabled(Array(repeating: .skipped, count: 7), putBack: nil))
        var mixed = Array(repeating: StepZeroView.Word.done, count: 7)
        mixed[2] = .partial
        #expect(StepZeroView.showReportEnabled(mixed, putBack: nil) == false)
        mixed[2] = .stopped
        #expect(StepZeroView.showReportEnabled(mixed, putBack: nil) == false)
        #expect(StepZeroView.showReportEnabled(Array(repeating: .done, count: 7), putBack: .notRun) == false)
        #expect(StepZeroView.showReportEnabled(Array(repeating: .done, count: 7), putBack: .skipped))
        #expect(StepZeroView.showReportEnabled([], putBack: nil) == false)
        let hidden = StepZeroView.hosted(
            words: notRun,
            line: nil,
            showNeeds: false,
            owesRestore: false,
            putBackWord: .done,
            grantsOn: [],
            grantsBack: [],
            notPutBack: [],
            digest: nil
        )
        #expect(hidden.prose.contains(StepZeroView.putBack) == false)
    }

    @Test func windowSharingIsNone() {
        #expect(StepZeroWindow.sharingType == .none)
        #expect(StepZeroWindow.title == "Step zero")
        #expect(StepZeroWindow.width == 560)
        #expect(StepZeroWindow.activation == .regular)
        #expect(StepZeroWindow.readsScreenSharingSetting == false)
        #expect(StepZeroView.motion == .still)
        #expect(StepZeroView.rows.count == 7)
    }

    @Test func watchdogKeepsOneTimer() {
        #expect(StepZeroWatchdog.arm(seconds: 0, after: nil) == nil)
        let first = StepZeroWatchdog.arm(seconds: 5, after: nil)
        let second = StepZeroWatchdog.arm(seconds: 10, after: first)
        #expect(first?.generation == 1)
        #expect(first?.seconds == 5)
        #expect(second?.generation == 2)
        #expect(second?.seconds == 10)
        #expect(StepZeroWatchdog.fire(generation: first?.generation ?? 0, current: second) == nil)
        let fired = StepZeroWatchdog.fire(generation: second?.generation ?? 0, current: second)
        #expect(fired?.exitCode == 70)
        #expect(fired?.step == .timedOut)
        #expect(fired?.closesWindow == false)
        #expect(fired?.closesSpace == false)
        #expect(fired?.restores == [.listeningMode, .defaultOutput, .stopChild])
    }
}

@MainActor
private final class FinishSection: StepZeroSection {
    var calls = 0
    func run() async { calls += 1 }
}

@MainActor
private final class HangSection: StepZeroSection {
    var calls = 0
    func run() async {
        calls += 1
        while !Task.isCancelled {
            await Task.yield()
        }
    }
}

@MainActor
private func until(_ ready: @MainActor () -> Bool) async {
    for _ in 0..<100 {
        if ready() { return }
        await Task.yield()
    }
}
