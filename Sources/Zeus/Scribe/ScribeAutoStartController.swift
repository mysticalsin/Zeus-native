import AVFoundation
import Foundation
import ZeusCore

/// What the meeting-start controller needs from Scribe. `ScribeController` is the production conformance; a test
/// supplies its own, so the controller runs with no capture.
@MainActor
protocol ScribeStartPort: AnyObject {
    var phase: ScribePhase { get }
    /// Called after every change of `phase`, in the same turn.
    var onPhaseChange: ((ScribePhase) -> Void)? { get set }
    func start(context: ScribeMeetingContext?)
    /// Throws away the recording of this session and saves nothing. Another session is left alone.
    func cancel(session: ScribeSessionID)
    /// Ends the recording at once, without opening the end window.
    func endNow()
    func suggestEnd()
    func withdrawEndSuggestion()
}

/// One pending wake. Setting a new one replaces the old; nil cancels it.
@MainActor
protocol ScribeOneShotScheduling: AnyObject {
    func schedule(after delay: TimeInterval?, fire: @escaping @MainActor () -> Void)
}

/// The shipped scheduler: one timer on the main run loop in the common modes, so a menu being tracked or a drag
/// does not hold it back. Nothing repeats.
@MainActor
final class ScribeRunLoopScheduler: ScribeOneShotScheduling {
    private var timer: Timer?

    func schedule(after delay: TimeInterval?, fire: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = nil
        guard let delay else { return }
        let timer = Timer(timeInterval: max(0, delay), repeats: false) { _ in
            MainActor.assumeIsolated { fire() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// Performs what the core `ScribeAutoStartMachine` decides. It reads the signals the call watcher already
/// gathers (calendar, running call apps, which process holds the microphone) and the facts a start needs at the
/// moment of each event (Scribe's phase, Microphone access, the readiness of an automatic start), asks the
/// machine, then performs its effects, draws `machine.card(now:)` and sets one wake at `machine.nextWake(now:)`.
/// A detector signal only suggests an end; it never stops a recording. It never asks for any permission:
/// automatic start needs the owner's click in Settings, Microphone already allowed and one earlier recording,
/// otherwise the machine asks instead.
@MainActor
final class ScribeAutoStartController {
    /// The shipped composition: the real Scribe, the run loop, the card panel and the system's microphone answer.
    static let shared: ScribeAutoStartController = {
        let panel = ScribeMeetingCardPanel(actions: ScribeMeetingCardPanel.Actions(
            primary: { card in ScribeAutoStartController.shared.primary(card) },
            cancel: { card in ScribeAutoStartController.shared.cancel(card) },
            dismiss: { card in ScribeAutoStartController.shared.dismiss(card) },
            pointer: { inside in ScribeAutoStartController.shared.pointer(inside: inside) }
        ))
        return ScribeAutoStartController(
            scribe: ScribeController.shared,
            clock: { ProcessInfo.processInfo.systemUptime },
            scheduler: ScribeRunLoopScheduler(),
            panel: panel,
            microphone: { ScribeMicrophoneAccess(authorizationRaw: AVCaptureDevice.authorizationStatus(for: .audio).rawValue) }
        )
    }()

    private(set) var machine = ScribeAutoStartMachine()
    /// The card last handed to the panel.
    private(set) var drawn: ScribeMeetingCard = .hidden

    private let scribe: ScribeStartPort
    private let clock: () -> TimeInterval
    private let scheduler: ScribeOneShotScheduling
    private let panel: ScribeMeetingCardRendering
    private let microphone: () -> ScribeMicrophoneAccess
    private var lastLogged = ScribeAutoStartMachine().state.logName

    init(scribe: ScribeStartPort, clock: @escaping () -> TimeInterval, scheduler: ScribeOneShotScheduling,
         panel: ScribeMeetingCardRendering, microphone: @escaping () -> ScribeMicrophoneAccess) {
        self.scribe = scribe
        self.clock = clock
        self.scheduler = scheduler
        self.panel = panel
        self.microphone = microphone
        scribe.onPhaseChange = { [weak self] phase in self?.scribeChanged(phase) }
    }

    /// Once per launch, before anything reads the opt-in stamp or touches `ScribeController.shared`: carries an
    /// old consent over only while "Start automatically" is the choice, removes a stale stamp, and notes that a
    /// Mac that already holds a saved meeting has recorded before. Reads the meetings folder, never loads a meeting.
    static func migrateOptInAtLaunch() {
        let saved = (try? FileManager.default.contentsOfDirectory(atPath: ScribeMeetingStore.standard.directory.path))?
            .contains { $0.hasSuffix(".json") } ?? false
        ScribeAutoStartOptIn.migrate(mode: ScribeAutoStartMode.current(), hasSavedMeetings: saved)
    }

    /// Whether a card is on screen. The heads-up card keeps out of its way.
    var isCardVisible: Bool { drawn != .hidden }

    // MARK: Input

    /// One reading from the call watcher, every poll and every microphone wake-up.
    func ingest(scan: ScribeCallScan, slots: [ScribeCalendarSlot], date: Date) {
        let mode = ScribeAutoStartMode.current()
        // A stamp that outlived its choice (a raw defaults write, say) is removed before it can be read.
        ScribeAutoStartOptIn.reconcile(mode: mode)
        let evidence = ScribeMeetingEvidence(
            date: date,
            slots: slots,
            micApps: scan.calls.map(\.app),
            presentApps: scan.runningCallApps.map(\.app),
            mode: mode,
            context: startContext(mode: mode),
            callWindows: scan.callWindows
        )
        send(.evidence(evidence, now: clock()))
    }

    /// The primary button of the card the person saw: Record, Allow, Try again or Switch.
    func primary(_ card: ScribeMeetingCard) {
        send(.primary(on: card, now: clock(), context: startContext()))
    }

    func cancel(_ card: ScribeMeetingCard) {
        send(.cancel(on: card, now: clock()))
    }

    func dismiss(_ card: ScribeMeetingCard) {
        send(.dismiss(on: card, now: clock()))
    }

    /// The pointer is over the card: it does not leave under the hand about to tap it.
    func pointer(inside: Bool) {
        send(.pointer(inside: inside, now: clock()))
    }

    /// The scheduled wake: deadlines, the countdown's digit, the minute on the card.
    func wake() {
        send(.tick(now: clock(), context: startContext()))
        // A quiet spell only counts on evidence, so while the call looks over, read the signals again each second.
        if machine.needsFreshEvidence { ScribeCallWatcher.shared.pollNow() }
    }

    /// Forgets the machine and takes the card down.
    func stop() {
        machine = ScribeAutoStartMachine()
        lastLogged = machine.state.logName
        scheduler.schedule(after: nil) {}
        render()
    }

    // MARK: Machine

    private func startContext(mode: ScribeAutoStartMode = ScribeAutoStartMode.current()) -> ScribeStartContext {
        let access = microphone()
        let readiness = ScribeAutoStartReadiness.resolve(
            mode: mode,
            optIn: ScribeAutoStartOptIn.date() != nil,
            microphone: access,
            hasRecorded: ScribeAutoStartOptIn.hasRecorded()
        )
        return ScribeStartContext(scribe: scribe.phase, microphone: access, automatic: readiness)
    }

    private func send(_ event: ScribeAutoStartMachine.Event) {
        let before = machine.state
        let effects = machine.handle(event)
        if case .primary(let card, _, _) = event, effects.isEmpty, machine.state == before {
            Self.log("tap ignored", "\(card.meeting?.key ?? "none") while \(before.logName)")
        }
        perform(effects)
        refresh()
    }

    /// Scribe's phase changed. The machine reads it at once; a meeting held for Scribe is looked at in the next
    /// turn, because starting from here would re-enter the transition that is still being applied.
    private func scribeChanged(_ phase: ScribePhase) {
        perform(machine.handle(.scribe(phase, now: clock())))
        refresh()
        if case .held = machine.state {
            Task { @MainActor [weak self] in self?.wake() }
        }
    }

    private func perform(_ effects: [ScribeAutoStartMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .start(let meeting):
                startScribe(for: meeting)
                // `ScribeController.start` reaches `.starting` at once, or refuses: read the phase in the same turn.
                perform(machine.handle(.scribe(scribe.phase, now: clock())))
            case .abandonStart(let session):
                Self.log("abandon", "session \(session)")
                scribe.cancel(session: session)
            case .openMicrophoneSettings:
                Self.log("open settings", "Privacy_Microphone")
                ScribeSettingsLink.open(pane: "Privacy_Microphone")
            case .suggestEnd:
                scribe.suggestEnd()
            case .withdrawEnd:
                scribe.withdrawEndSuggestion()
            case .endNow:
                Self.log("switch", "ending the recording now")
                scribe.endNow()
            }
        }
    }

    private func startScribe(for meeting: ScribeMeeting) {
        Self.log("start", "meeting \(meeting.key)")
        // Only a live call has a process to follow; a calendar start has no call binding.
        let identity = meeting.isLive
            ? meeting.callApp.flatMap { ScribeCallWatcher.shared.recordingIdentity(for: .callDetected($0)) }
            : nil
        scribe.start(context: meeting.context(callIdentity: identity))
    }

    /// After every event: log a change of state once, draw the card the state gives, set the one wake.
    private func refresh() {
        let line = machine.state.logName
        if line != lastLogged {
            lastLogged = line
            NSLog("[ZEUS] scribe meeting: %@", line)
            FlightRecorder.shared.record("scribe", "meeting state", line)
        }
        render()
        let now = clock()
        if let wake = machine.nextWake(now: now) {
            scheduler.schedule(after: max(0, wake - now)) { [weak self] in self?.wake() }
        } else {
            scheduler.schedule(after: nil) {}
        }
    }

    private func render() {
        drawn = machine.card(now: clock())
        panel.render(drawn)
    }

    private static func log(_ stage: String, _ detail: String) {
        NSLog("[ZEUS] scribe meeting: %@ %@", stage, detail)
        FlightRecorder.shared.record("scribe", "meeting \(stage)", detail)
    }
}
