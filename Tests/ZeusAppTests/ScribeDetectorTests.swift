import AppKit
import EventKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

private let sdBase = Date(timeIntervalSince1970: 3_500_000)

private func sdSlot(_ id: String, start: TimeInterval, end: TimeInterval? = nil) -> ScribeCalendarSlot {
    ScribeCalendarSlot(id: id, title: "Meeting \(id)", start: sdBase.addingTimeInterval(start),
                       end: end.map { sdBase.addingTimeInterval($0) }, hasCallLink: true, callApp: .teams)
}

/// The watcher with every outside thing replaced: the clock, the setting, the calendar, the scan (which waits for
/// the test to finish it), the microphone listeners, the one wake-up and both notification centers.
@MainActor
private final class Harness {
    final class Scheduler: ScribeOneShotScheduling {
        var delay: TimeInterval?
        var fire: (@MainActor () -> Void)?
        var scheduled = 0
        func schedule(after delay: TimeInterval?, fire: @escaping @MainActor () -> Void) {
            self.delay = delay
            self.fire = delay == nil ? nil : fire
            if delay != nil { scheduled += 1 }
        }
        func wakeUp() {
            guard let run = fire else { return }
            fire = nil
            delay = nil
            run()
        }
    }

    final class Listener: ScribeMicObserving {
        var started = 0
        var stopped = 0
        func start() { started += 1 }
        func stop() { stopped += 1 }
    }

    var mode = ScribeAutoStartMode.ask
    var idle = true
    var now = sdBase
    var calendar: [ScribeCalendarSlot] = []
    var calls: [ScribeDetectedCall] = []
    var scans = 0
    var calendarReads = 0
    /// How far ahead each calendar read asked.
    var lookAheads: [TimeInterval] = []
    var ingested: [(calls: Int, slots: Int)] = []
    var resets = 0
    var exits: [ScribeCallProcessIdentity] = []
    /// A test that runs the real meeting-start controller behind the watcher connects it here.
    var idleSource: (() -> Bool)?
    var onIngest: ((ScribeCallScan, [ScribeCalendarSlot], Date) -> Void)?
    var onReset: (() -> Void)?
    var waiting: [CheckedContinuation<ScribeCallScan, Never>] = []
    var listeners: [Listener] = []
    var micHandlers: [@MainActor @Sendable () -> Void] = []
    let scheduler = Scheduler()
    let workspace = NotificationCenter()
    let notifications = NotificationCenter()
    private(set) var watcher: ScribeCallWatcher!

    init() {
        watcher = ScribeCallWatcher(
            ports: .init(
                mode: { [unowned self] in mode },
                machineIdle: { [unowned self] in idleSource?() ?? idle },
                slots: { [unowned self] _, lookAhead in
                    calendarReads += 1
                    lookAheads.append(lookAhead)
                    return calendar
                },
                scan: { [unowned self] in
                    scans += 1
                    return await withCheckedContinuation { waiting.append($0) }
                },
                ingest: { [unowned self] scan, slots, date in
                    ingested.append((scan.calls.count, slots.count))
                    onIngest?(scan, slots, date)
                },
                reset: { [unowned self] in
                    resets += 1
                    onReset?()
                },
                terminated: { [unowned self] in exits.append($0) },
                now: { [unowned self] in now }),
            micObserver: { [unowned self] onChange in
                let listener = Listener()
                listeners.append(listener)
                micHandlers.append(onChange)
                return listener
            },
            scheduler: scheduler,
            workspaceCenter: workspace,
            notificationCenter: notifications)
    }

    /// Lets the scan task the watcher started run up to its first wait.
    func settle() async {
        for _ in 0..<8 { await Task.yield() }
    }

    /// Finishes the oldest waiting scan with the calls now set, then lets the watcher react.
    func finishScan() async {
        await settle()
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume(returning: ScribeCallScan(calls: calls))
        await settle()
    }
}

/// Scribe as the meeting-start controller sees it, with nothing recording.
@MainActor
private final class IdleScribe: ScribeStartPort {
    var phase: ScribePhase = .idle
    var onPhaseChange: ((ScribePhase) -> Void)?
    private(set) var starts = 0
    func start(context: ScribeMeetingContext?) { starts += 1 }
    func cancel(session: ScribeSessionID) {}
    func endNow() {}
    func suggestEnd() {}
    func withdrawEndSuggestion() {}
}

@MainActor
private final class DrawnCards: ScribeMeetingCardRendering {
    private(set) var latest: ScribeMeetingCard = .hidden
    func render(_ card: ScribeMeetingCard) { latest = card }
}

@MainActor
@Suite("Scribe detector")
struct ScribeDetectorTests {
    @Test func offStopsTheDetector() async {
        let harness = Harness()
        harness.mode = .off
        harness.watcher.follow()
        await harness.settle()
        #expect(!harness.watcher.isRunning)
        #expect(harness.scheduler.scheduled == 0)
        #expect(harness.scheduler.delay == nil)
        #expect(harness.listeners.isEmpty)
        #expect(harness.scans == 0)
        #expect(harness.calendarReads == 0)
    }

    @Test func switchingToAskMeStartsTheDetector() async {
        let harness = Harness()
        harness.mode = .off
        harness.watcher.follow()
        harness.mode = .ask
        harness.watcher.follow()
        #expect(harness.watcher.isRunning)
        #expect(harness.listeners.count == 1)
        #expect(harness.listeners.first?.started == 1)
        await harness.finishScan()
        #expect(harness.scans == 1)
        #expect(harness.ingested.count == 1)
    }

    @Test func switchingToOffStopsEverythingAtOnce() async {
        let harness = Harness()
        harness.watcher.follow()
        await harness.finishScan()
        #expect(harness.scheduler.delay != nil)
        harness.mode = .off
        harness.watcher.follow()
        #expect(!harness.watcher.isRunning)
        #expect(harness.listeners.first?.stopped == 1)
        #expect(harness.scheduler.delay == nil)
        #expect(harness.resets == 1)
    }

    @Test func offWhileTheMachineIsBusyKeepsReadingUntilItIsIdle() async {
        let harness = Harness()
        harness.mode = .off
        harness.idle = false
        harness.watcher.follow()
        #expect(harness.watcher.isRunning)
        await harness.finishScan()
        #expect(harness.watcher.plan == .polling)
        harness.idle = true
        harness.scheduler.wakeUp()
        await harness.finishScan()
        #expect(!harness.watcher.isRunning)
        #expect(harness.listeners.first?.stopped == 1)
        #expect(harness.scheduler.delay == nil)
    }

    @Test func aWakeDuringAScanRunsExactlyOneMoreScan() async {
        let harness = Harness()
        harness.watcher.follow()
        await harness.settle()
        #expect(harness.scans == 1)
        harness.micHandlers[0]()
        harness.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        harness.notifications.post(name: .EKEventStoreChanged, object: nil)
        await harness.settle()
        #expect(harness.scans == 1)
        await harness.finishScan()
        #expect(harness.scans == 2)
        await harness.finishScan()
        #expect(harness.scans == 2)
        #expect(harness.waiting.isEmpty)
        #expect(harness.ingested.count == 2)
    }

    @Test func nothingNearListensWithOneWakeAndNoRepeatingTimer() async {
        let harness = Harness()
        harness.calendar = [sdSlot("later", start: 3_600)]
        harness.watcher.follow()
        await harness.finishScan()
        #expect(harness.watcher.plan == .listening(wakeAt: sdBase.addingTimeInterval(3_600 - 120)))
        #expect(harness.scheduler.delay == TimeInterval(3_480))
        harness.now = sdBase.addingTimeInterval(1_000)
        harness.scheduler.wakeUp()
        await harness.finishScan()
        #expect(harness.scans == 2)
        #expect(harness.scheduler.delay == TimeInterval(2_480))
    }

    @Test func aMeetingNearPollsEveryFiveSeconds() async {
        let harness = Harness()
        harness.calendar = [sdSlot("soon", start: 60)]
        harness.watcher.follow()
        await harness.finishScan()
        #expect(harness.watcher.plan == .polling)
        #expect(harness.scheduler.delay == 5)
        harness.scheduler.wakeUp()
        await harness.finishScan()
        #expect(harness.scans == 2)
    }

    @Test func aCallHoldingTheMicrophonePollsWithNothingOnTheCalendar() async {
        let harness = Harness()
        harness.calls = [ScribeDetectedCall(app: .zoom, pid: nil)]
        harness.watcher.follow()
        await harness.finishScan()
        #expect(harness.watcher.plan == .polling)
        #expect(harness.scheduler.delay == 5)
    }

    @Test func aCalendarChangeResetsTheWake() async {
        let harness = Harness()
        harness.calendar = [sdSlot("later", start: 7_200)]
        harness.watcher.follow()
        await harness.finishScan()
        #expect(harness.scheduler.delay == TimeInterval(7_080))
        harness.calendar = [sdSlot("moved", start: 1_800)]
        harness.notifications.post(name: .EKEventStoreChanged, object: nil)
        await harness.finishScan()
        #expect(harness.scheduler.delay == TimeInterval(1_680))
    }

    @Test func aWakeFromSleepReadsTheSignalsAgain() async {
        let harness = Harness()
        harness.watcher.follow()
        await harness.finishScan()
        harness.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        await harness.finishScan()
        #expect(harness.scans == 2)
    }

    @Test func aScanThatEndsAfterTheDetectorStoppedIsDropped() async {
        let harness = Harness()
        harness.watcher.follow()
        await harness.settle()
        harness.mode = .off
        harness.watcher.follow()
        #expect(!harness.watcher.isRunning)
        await harness.finishScan()
        #expect(harness.ingested.isEmpty)
        #expect(harness.scheduler.delay == nil)
    }

    @Test func aScanThatNeverReturnsIsGivenUpOnAndTheNextWakeScansAgain() async {
        let harness = Harness()
        harness.watcher.follow()
        await harness.settle()
        #expect(harness.scans == 1)
        // The probe hangs. The watcher bounds the scan through its scheduler instead of waiting forever.
        #expect(harness.scheduler.delay != nil, "a scan in flight has a deadline")
        harness.scheduler.wakeUp()
        await harness.settle()
        #expect(harness.ingested.count == 1, "the gave-up scan ends as an empty reading")
        #expect(harness.ingested.first?.calls == 0)
        #expect(harness.scheduler.delay != nil, "the plan sets the next wake")

        // The hung probe answers late: that reading belongs to a scan already given up and is dropped.
        harness.calls = [ScribeDetectedCall(app: .zoom, pid: nil)]
        await harness.finishScan()
        #expect(harness.ingested.count == 1)

        harness.scheduler.wakeUp()
        await harness.settle()
        #expect(harness.scans == 2, "the gate is free again, so the next wake scans")
        await harness.finishScan()
    }

    @Test func pollingScansReadAShortWindowAndOnlyAListeningPlanReadsTheFullLookAhead() async {
        let near = ScribeMeetingStartPolicy.leadWindow
        let polling = Harness()
        polling.calendar = [sdSlot("soon", start: 60)]
        polling.watcher.follow()
        await polling.finishScan()
        #expect(polling.watcher.plan == .polling)
        polling.scheduler.wakeUp()
        await polling.finishScan()
        #expect(polling.lookAheads == [near, near], "every polling scan asks for the short window only")

        let listening = Harness()
        listening.calendar = [sdSlot("later", start: 3_600)]
        listening.watcher.follow()
        await listening.finishScan()
        #expect(listening.lookAheads == [near, ScribeDetectorPlan.lookAhead],
                "the full look-ahead is read once, to choose the wake")
        #expect(listening.watcher.plan == .listening(wakeAt: sdBase.addingTimeInterval(3_600 - 120)))
        #expect(listening.scheduler.delay == TimeInterval(3_480))
    }

    @Test func theExitObserverWatchesWhileOffAndBusyAndIsRemovedByHalt() async throws {
        // The observer reads a real app's pid, bundle id and launch date. Apps opened at login carry no launch date, so on
        // a fresh runner (GitHub's) none may qualify: then a hidden Calculator is opened for the test and quit after it.
        let qualifies = { (app: NSRunningApplication) in
            app.processIdentifier > 0 && app.bundleIdentifier != nil && app.launchDate != nil
        }
        var opened: NSRunningApplication?
        defer { opened?.terminate() }
        let app: NSRunningApplication
        if let running = NSWorkspace.shared.runningApplications.first(where: qualifies) {
            app = running
        } else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            opened = try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Applications/Calculator.app"), configuration: configuration)
            app = try #require(opened.flatMap { qualifies($0) ? $0 : nil })
        }
        let exit = { (harness: Harness) in
            harness.workspace.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                   userInfo: [NSWorkspace.applicationUserInfoKey: app])
        }
        let harness = Harness()
        harness.mode = .off
        harness.idle = false
        harness.watcher.follow()
        await harness.settle()
        #expect(harness.watcher.isRunning, "Off with a busy machine keeps the detector reading")
        exit(harness)
        await harness.settle()
        #expect(harness.exits.count == 1, "a recording bound to the app still hears that it quit")

        harness.idle = true
        harness.watcher.follow()
        #expect(!harness.watcher.isRunning)
        exit(harness)
        await harness.settle()
        #expect(harness.exits.count == 1, "halt removed the observer")
    }

    @Test func offThenAskInsideTheMeetingWindowShowsNoCardForAMeetingAlreadyDismissed() async throws {
        let suite = NSTemporaryDirectory() + "scribe-detector-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = FeatureSettings.key(ScribeAutoStartMode.settingID)
        let cards = DrawnCards()
        let controller = ScribeAutoStartController(
            scribe: IdleScribe(), clock: { 100 }, scheduler: Harness.Scheduler(), panel: cards,
            microphone: { .allowed }, defaults: defaults)
        let harness = Harness()
        harness.calendar = [sdSlot("standup", start: 100, end: 1_900)]
        harness.idleSource = { controller.isIdle }
        harness.onIngest = { controller.ingest(scan: $0, slots: $1, date: $2) }
        harness.onReset = { controller.stop() }

        // Ask: the heads-up shows, and the owner dismisses it.
        defaults.set(ScribeAutoStartMode.ask.title, forKey: key)
        harness.mode = ScribeAutoStartMode.current(defaults: defaults)
        harness.watcher.follow()
        await harness.finishScan()
        let offer = cards.latest
        guard case .offer = offer else {
            Issue.record("the heads-up did not draw an offer: \(offer)")
            return
        }
        controller.dismiss(offer)
        #expect(cards.latest == .hidden)

        // Off stops the detector and the machine; back to Ask, still before the meeting starts.
        defaults.set(ScribeAutoStartMode.off.title, forKey: key)
        harness.mode = ScribeAutoStartMode.current(defaults: defaults)
        harness.watcher.follow()
        #expect(!harness.watcher.isRunning)
        #expect(harness.resets == 1)
        defaults.set(ScribeAutoStartMode.ask.title, forKey: key)
        harness.mode = ScribeAutoStartMode.current(defaults: defaults)
        harness.now = sdBase.addingTimeInterval(30)
        harness.watcher.follow()
        await harness.finishScan()
        #expect(harness.watcher.isRunning)
        #expect(cards.latest == .hidden, "a dismissed meeting stays dismissed across Off and back")
        #expect(controller.machine.ledger.mark(ofSlot: harness.calendar[0].id) == .declined)
    }

    @Test func aStoppedDetectorIgnoresEveryWake() async {
        let harness = Harness()
        harness.watcher.follow()
        await harness.finishScan()
        harness.mode = .off
        harness.watcher.follow()
        harness.scheduler.wakeUp()
        harness.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        harness.notifications.post(name: .EKEventStoreChanged, object: nil)
        harness.micHandlers[0]()
        await harness.settle()
        #expect(harness.scans == 1)
    }
}

@Suite("Scribe calendar reader")
struct ScribeCalendarReaderTests {
    private func event(title: String? = "Review", start: TimeInterval = 600, guests: [String] = ["Marie"],
                       declined: Bool = false, allDay: Bool = false, canceled: Bool = false,
                       links: [String?] = []) -> ScribeCalendarReader.Event {
        ScribeCalendarReader.Event(
            identifier: "e1", title: title, start: sdBase.addingTimeInterval(start),
            end: sdBase.addingTimeInterval(start + 1_800), isAllDay: allDay, isCanceled: canceled,
            hasAttendees: !guests.isEmpty, declinedByMe: declined, attendeeNames: guests, linkTexts: links)
    }

    @Test func aMeetingTheCurrentUserDeclinedIsNotAMeeting() {
        #expect(ScribeCalendarReader.slot(from: event()) != nil)
        #expect(ScribeCalendarReader.slot(from: event(declined: true)) == nil)
        #expect(ScribeCalendarReader.slot(from: event(declined: true, links: ["https://zoom.us/j/1"])) == nil)
    }

    @Test func anAllDayOrCanceledEventIsNotAMeeting() {
        #expect(ScribeCalendarReader.slot(from: event(allDay: true)) == nil)
        #expect(ScribeCalendarReader.slot(from: event(canceled: true)) == nil)
    }

    @Test func aReminderToYourselfIsNotAMeeting() {
        #expect(ScribeCalendarReader.slot(from: event(guests: [])) == nil)
        #expect(ScribeCalendarReader.slot(from: event(guests: [], links: ["https://zoom.us/j/1"])) != nil)
    }

    @Test func theSlotCarriesTheLinkTheAppAndOnlyDisplayNames() throws {
        let slot = try #require(ScribeCalendarReader.slot(from: event(
            guests: ["Marie", "marie@example.com"], links: [nil, "Join https://meet.google.com/abc-defg-hij"])))
        #expect(slot.id == "e1@\(Int(sdBase.addingTimeInterval(600).timeIntervalSince1970))")
        #expect(slot.title == "Review")
        #expect(slot.hasCallLink)
        #expect(slot.callApp == .meet)
        #expect(slot.attendeeNames == ["Marie"])
    }

    @Test func aMissingTitleReadsAsMeeting() throws {
        #expect(try #require(ScribeCalendarReader.slot(from: event(title: nil))).title == "Meeting")
    }
}
