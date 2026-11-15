import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

private let journeyBase = Date(timeIntervalSince1970: 1_800_000_000)

/// The capture provider of `ScribeLifecycleScenarioTests`: it records what Scribe asks of it and reports only what
/// a test sends. Nothing is captured.
private final class JourneyCapture: ScribeCaptureProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (ScribeCaptureEvent) -> Void)?
    private var sessions: [ScribeSessionID] = []
    private var stops = 0
    var startCount: Int { lock.withLock { sessions.count } }
    var stopCount: Int { lock.withLock { stops } }

    func start(session: ScribeSessionID, frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
               events: @escaping @Sendable (ScribeCaptureEvent) -> Void) {
        lock.withLock {
            sessions.append(session)
            callback = events
        }
    }

    func stop(session: ScribeSessionID) { lock.withLock { stops += 1 } }
    func send(_ event: ScribeCaptureEvent) { lock.withLock { callback }?(event) }
}

/// The one wake the controller asks for. A test decides when it fires, after moving the clock.
@MainActor
private final class JourneyScheduler: ScribeOneShotScheduling {
    private(set) var delay: TimeInterval?
    private var fire: (@MainActor () -> Void)?

    func schedule(after delay: TimeInterval?, fire: @escaping @MainActor () -> Void) {
        self.delay = delay
        self.fire = delay == nil ? nil : fire
    }

    /// Runs the pending wake, as the run loop would when its time comes.
    func wake() {
        guard let run = fire else { return }
        fire = nil
        delay = nil
        run()
    }
}

private struct JourneyRefusal: LocalizedError {
    var errorDescription: String? { "Synthetic capture refusal" }
}

private enum JourneyFailure: Error { case timedOut(String) }

/// The clock the controller, Scribe and the card panel all read: machine uptime and wall time move together.
private final class JourneyTime {
    var uptime: TimeInterval = 100
    var date = journeyBase
}

/// Everything the card meets in the app, with the outside replaced: the real controller, the real Scribe over an
/// inert capture provider, the real card panel on a made-up screen far from every display, the owned-window
/// driver, a manual wake and a throwaway settings suite.
@MainActor
private final class Journey {
    /// Far from every display, so a test never flashes a window.
    static let screen = CGRect(x: -30_000, y: -30_000, width: 1440, height: 900)

    private final class Link {
        weak var controller: ScribeAutoStartController?
    }

    let time = JourneyTime()
    let capture = JourneyCapture()
    let scheduler = JourneyScheduler()
    let registry = OwnedWindowControlRegistry()
    let driver: OwnedWindowEventDriver
    let defaults: UserDefaults
    let root: URL
    let store: ScribeMeetingStore
    let scribe: ScribeController
    let panel: ScribeMeetingCardPanel
    let controller: ScribeAutoStartController
    private let suite = "scribe-card-journey-\(UUID().uuidString)"

    /// `automatic` sets what an automatic start needs: the choice, the owner's click, one earlier recording and
    /// Microphone access. Otherwise the choice is the default, Ask me.
    init(automatic: Bool = false) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if automatic {
            defaults.set(ScribeAutoStartMode.automatic.title, forKey: FeatureSettings.key(ScribeAutoStartMode.settingID))
            ScribeAutoStartOptIn.record(mode: .automatic, now: journeyBase, defaults: defaults)
            ScribeAutoStartOptIn.noteRecordingBegan(now: journeyBase, defaults: defaults)
        }
        self.defaults = defaults
        root = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-card-journey-\(UUID().uuidString)")
        store = ScribeMeetingStore(directory: root)
        let time = self.time
        scribe = ScribeController(provider: capture, monotonicClock: { time.uptime }, store: store,
                                  cancellationDefaults: defaults, optInDefaults: defaults,
                                  transcriptionEngine: { .apple })
        let link = Link()
        panel = ScribeMeetingCardPanel(
            actions: .init(primary: { link.controller?.primary($0) }, cancel: { link.controller?.cancel($0) },
                           dismiss: { link.controller?.dismiss($0) }, pointer: { link.controller?.pointer(inside: $0) }),
            now: { time.date },
            uptime: { time.uptime },
            visibleFrame: { Self.screen },
            // A fade ends at once, so a card that is taken down is gone when the render call returns.
            fade: { panel, alpha, done in
                panel.alphaValue = alpha
                done?()
            },
            journeyRegistry: registry)
        controller = ScribeAutoStartController(
            scribe: scribe, clock: { time.uptime }, scheduler: scheduler, panel: panel,
            microphone: { .allowed }, defaults: defaults)
        link.controller = controller
        driver = OwnedWindowEventDriver(registry: registry)
    }

    /// Moves machine time and wall time together.
    func advance(_ seconds: TimeInterval) {
        time.uptime += seconds
        time.date = time.date.addingTimeInterval(seconds)
    }

    /// One reading from the call watcher: the calls that hold the microphone and the calendar.
    func ingest(calls: [ScribeCallApp] = [], slots: [ScribeCalendarSlot] = []) {
        let scan = ScribeCallScan(calls: calls.map { ScribeDetectedCall(app: $0, pid: nil) })
        controller.ingest(scan: scan, slots: slots, date: time.date)
    }

    /// Clicks the real control with this identifier in the real card window.
    func click(_ id: String) async throws {
        let window = try #require(panel.window)
        driver.register(window)
        try await driver.click(id, in: window)
    }

    func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw JourneyFailure.timedOut(what)
    }

    /// The words the card shows now: its status, from the card and the wall time the panel handed to the view.
    var shownStatus: String? {
        panel.hostedView.map { ScribeMeetingCardText.status($0.card, now: $0.now) }
    }

    /// Everything the test made, taken down. Not an asserted action.
    func teardown() {
        scribe.cancel()
        if let window = panel.window { OwnedWindowFixtureApplication.close(window) }
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private func slot(_ title: String = "Weekly sync", startsIn seconds: TimeInterval) -> ScribeCalendarSlot {
    ScribeCalendarSlot(id: "slot-\(title)", title: title, start: journeyBase.addingTimeInterval(seconds),
                       hasCallLink: true, callApp: .zoom)
}

/// The meeting card as a person meets it: the real panel on screen, its real controls clicked with events sent to
/// the owned window, a fake clock, and the real controller and Scribe behind them. Evidence is synthetic and enters
/// through `ingest`. No device, calendar, permission prompt or capture is involved, and this is not device proof.
@MainActor @Suite("Scribe meeting card journey", .serialized)
struct ScribeMeetingCardJourneyTests {
    @Test func theRealRecordButtonStartsExactlyOneSession() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let journey = Journey()
            defer { journey.teardown() }
            journey.ingest(slots: [slot(startsIn: 120)])
            guard case .offer(let meeting, let blocked) = journey.panel.drawnCard else {
                Issue.record("the heads-up did not draw an offer: \(journey.panel.drawnCard)")
                return
            }
            #expect(blocked == nil)
            #expect(journey.panel.isOnScreen)
            #expect(journey.capture.startCount == 0)

            try await journey.click("scribe.meetingCard.primary")
            try await journey.waitUntil("a session") { journey.scribe.phase.sessionID != nil }
            let session = try #require(journey.scribe.phase.sessionID)
            #expect(journey.capture.startCount == 1)
            #expect(journey.panel.drawnCard == .starting(meeting, cancellable: false))

            journey.capture.send(.captureAcknowledged(session))
            try await journey.waitUntil("recording") { journey.scribe.isRecording }
            #expect(journey.panel.drawnCard == .recording(meeting))
            #expect(journey.capture.startCount == 1)
            // Record is gone from the card, so there is no second start to click.
            let window = try #require(journey.panel.window)
            try await journey.waitUntil("Record removed") {
                journey.registry.probes(for: "scribe.meetingCard.primary", in: window).isEmpty
            }
            #expect(journey.capture.startCount == 1)
        }
    }

    @Test func theRealCancelEndsACountdownWithNoSession() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let journey = Journey(automatic: true)
            defer { journey.teardown() }
            journey.ingest(calls: [.zoom])
            #expect(!journey.panel.isOnScreen, "a call is checked for a few seconds before anything shows")
            journey.advance(3)
            journey.ingest(calls: [.zoom])
            guard case .countdown(let meeting, let seconds, let deadline, let total) = journey.panel.drawnCard else {
                Issue.record("the call did not draw a countdown: \(journey.panel.drawnCard)")
                return
            }
            #expect(seconds == 5 && deadline == 108 && total == 5)
            #expect(journey.panel.isOnScreen)
            #expect(journey.scheduler.delay == 1)

            try await journey.click("scribe.meetingCard.cancel")
            #expect(journey.controller.drawn == .hidden)
            #expect(!journey.panel.isOnScreen)
            #expect(journey.capture.startCount == 0)
            #expect(journey.scribe.phase == .idle)
            #expect(journey.scheduler.delay == nil)
            #expect(journey.controller.machine.ledger.mark(of: meeting) == .declined)

            journey.advance(1)
            journey.ingest(calls: [.zoom])
            #expect(journey.controller.drawn == .hidden, "the same call does not bring the card back")
            #expect(journey.capture.startCount == 0)
        }
    }

    @Test func aCountdownThatEndsReachesStartingThenRecording() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let journey = Journey(automatic: true)
            defer { journey.teardown() }
            journey.ingest(calls: [.zoom])
            journey.advance(3)
            journey.ingest(calls: [.zoom])
            guard case .countdown(let meeting, _, _, _) = journey.panel.drawnCard else {
                Issue.record("the call did not draw a countdown: \(journey.panel.drawnCard)")
                return
            }
            for left in [4, 3, 2, 1] {
                journey.advance(1)
                journey.scheduler.wake()
                #expect(journey.panel.drawnCard == .countdown(meeting, seconds: left, deadline: 108, total: 5))
                #expect(journey.capture.startCount == 0)
            }

            journey.advance(1)
            journey.scheduler.wake()
            #expect(journey.panel.drawnCard == .starting(meeting, cancellable: true))
            #expect(journey.capture.startCount == 1)
            let session = try #require(journey.scribe.phase.sessionID)

            journey.capture.send(.captureAcknowledged(session))
            try await journey.waitUntil("recording") { journey.scribe.isRecording }
            #expect(journey.panel.drawnCard == .recording(meeting))
            #expect(journey.scheduler.delay == 1.5)

            journey.advance(1.5)
            journey.scheduler.wake()
            #expect(journey.panel.drawnCard == .hidden, "the confirmation leaves on its own")
            #expect(!journey.panel.isOnScreen)
            #expect(journey.scribe.isRecording)
            #expect(journey.capture.startCount == 1)
        }
    }

    @Test func aCancelAfterTheCountdownEndedLeavesNoSessionAndNoSavedMeeting() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let journey = Journey(automatic: true)
            defer { journey.teardown() }
            journey.ingest(calls: [.zoom])
            journey.advance(3)
            journey.ingest(calls: [.zoom])
            let countdown = journey.panel.drawnCard
            guard case .countdown(let meeting, _, _, _) = countdown else {
                Issue.record("the call did not draw a countdown: \(countdown)")
                return
            }
            journey.advance(5)
            journey.scheduler.wake()
            #expect(journey.panel.drawnCard == .starting(meeting, cancellable: true))
            let session = try #require(journey.scribe.phase.sessionID)

            // The card that replaced the countdown still has its Cancel.
            try await journey.click("scribe.meetingCard.cancel")
            #expect(journey.scribe.phase == .idle)
            #expect(journey.capture.startCount == 1 && journey.capture.stopCount == 1)
            #expect(journey.controller.drawn == .hidden)
            #expect(!journey.panel.isOnScreen)

            // A tap on the countdown card the person saw, and a late answer from the provider, change nothing.
            journey.controller.cancel(countdown)
            journey.capture.send(.captureAcknowledged(session))
            try await Task.sleep(for: .milliseconds(50))
            #expect(journey.scribe.phase == .idle)
            #expect(journey.controller.drawn == .hidden)
            #expect(journey.scribe.recaps.isEmpty)
            #expect(journey.store.loadAll().records.isEmpty)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: journey.root.path)) ?? []
            #expect(files.filter { $0.hasSuffix(".json") }.isEmpty)

            journey.advance(1)
            journey.ingest(calls: [.zoom])
            #expect(journey.controller.drawn == .hidden, "the cancelled meeting is not offered again")
            #expect(journey.capture.startCount == 1)
        }
    }

    @Test func aProviderThatFailsShowsItsReason() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let journey = Journey()
            defer { journey.teardown() }
            journey.ingest(slots: [slot(startsIn: 60)])
            guard case .offer(let meeting, _) = journey.panel.drawnCard else {
                Issue.record("the heads-up did not draw an offer: \(journey.panel.drawnCard)")
                return
            }
            try await journey.click("scribe.meetingCard.primary")
            try await journey.waitUntil("a session") { journey.scribe.phase.sessionID != nil }
            let session = try #require(journey.scribe.phase.sessionID)

            journey.capture.send(.failed(session, JourneyRefusal()))
            let failed = ScribeMeetingCard.failed(meeting, .captureFailed("Synthetic capture refusal"))
            try await journey.waitUntil("the failure") { journey.panel.drawnCard == failed }
            #expect(journey.shownStatus == "Synthetic capture refusal")
            #expect(ScribeMeetingCardText.primary(failed) == "Try again")
            #expect(journey.panel.isOnScreen)
            #expect(journey.capture.startCount == 1)
        }
    }

    @Test func theRealDismissGlyphQuietsTheMeeting() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let journey = Journey()
            defer { journey.teardown() }
            let upcoming = slot(startsIn: 120)
            journey.ingest(slots: [upcoming])
            #expect(journey.panel.isOnScreen)

            try await journey.click("scribe.meetingCard.dismiss")
            #expect(journey.controller.drawn == .hidden)
            #expect(!journey.panel.isOnScreen)
            #expect(journey.controller.machine.ledger.mark(ofSlot: upcoming.id) == .declined)
            #expect(journey.scheduler.delay == nil)

            // The meeting starts: it stays quiet, and nothing records.
            journey.advance(120)
            journey.ingest(slots: [upcoming])
            #expect(journey.controller.drawn == .hidden)
            #expect(!journey.panel.isOnScreen)
            #expect(journey.capture.startCount == 0)
        }
    }

    @Test func theCardSitsAtThePlacementOriginOfItsScreen() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let journey = Journey()
            defer { journey.teardown() }
            journey.ingest(slots: [slot(startsIn: 120)])
            let window = try #require(journey.panel.window)
            let frame = window.frame
            let margin = ScribeMeetingCardPanel.margin
            #expect(frame.size.width == ScribeMeetingCardView.width)
            #expect(frame.origin == ScribeMeetingCardPlacement.origin(
                size: frame.size, visibleFrame: Journey.screen, margin: margin))
            // The same place, from the corner: top right, one margin in from each edge.
            #expect(frame.maxX == Journey.screen.maxX - margin)
            #expect(frame.maxY == Journey.screen.maxY - margin)
        }
    }

    @Test func theTimeOnTheCardChangesWhenTheClockCrossesTheMinute() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let journey = Journey()
            defer { journey.teardown() }
            journey.ingest(slots: [slot(startsIn: 75)])
            let card = journey.panel.drawnCard
            #expect(journey.shownStatus == "in 2 min")
            // The next wake is the minute change, 15 seconds on, not the card's own 20 seconds.
            #expect(journey.scheduler.delay == 15)

            journey.advance(15)
            journey.scheduler.wake()
            #expect(journey.panel.drawnCard == card, "the same card, drawn again with the new time")
            #expect(journey.panel.isOnScreen)
            #expect(journey.shownStatus == "in 1 min")
        }
    }
}
