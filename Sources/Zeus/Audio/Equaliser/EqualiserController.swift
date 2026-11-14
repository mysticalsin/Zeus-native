import AppKit
import Foundation
import Observation
import ZeusCore

/// Holds the one lifecycle state of per-app shaping and carries out what the reducer asks for. The reducer decides;
/// this class reads the world, builds the events and runs the effects. Nothing here touches Core Audio directly: taps,
/// probes, listeners, the claim and the clock all come in through ports, so a test never opens a real device.
///
/// Off by default. `setSwitch(true)` is the owner's request and the only way anything starts; `init` builds nothing
/// and installs nothing. The live ports come only from `AppDelegate`.
@MainActor
@Observable
final class EqualiserController: EqualiserControlling {
    typealias Life = EqualiserLifecycle
    typealias App = EqualiserPlayingGroup

    /// Written at the first muted build and removed on teardown. Present at launch means Zeus stopped while shaping.
    static let shapingSinceKey = "equaliser.shapingSince"
    static let launchNoticeText = "Zeus stopped while shaping sound. If an app is silent, quit and reopen it."
    static let probePollSeconds: TimeInterval = 0.25
    static let retargetCheckSeconds: TimeInterval = 2
    static let wakeDelaySeconds: TimeInterval = 2
    static let watchdogSeconds: TimeInterval = 1

    // MARK: What the card reads

    private(set) var status: EqualiserStatus
    private(set) var state: Life.State = .off
    /// True when the saved settings could not be read. The raw copy is kept under `AppSoundBook.unreadableKey`.
    private(set) var savedSettingsUnreadable = false
    /// Said once after a launch that follows a stop while shaping.
    private(set) var launchNotice: String?
    /// The last thing a save or an addition had to say, such as a full book.
    private(set) var message: String?

    // MARK: Ports

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let factory: any ShapingTapFactory
    @ObservationIgnored private let monitor: any EqualiserMonitoring
    @ObservationIgnored private let claim: any EqualiserClaiming
    @ObservationIgnored private let scheduler: any EqualiserScheduling
    @ObservationIgnored private let ownBundleID: String
    @ObservationIgnored private let ownPID: Int32
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let zeusCaptures: @MainActor () -> Bool
    @ObservationIgnored private let onProvenAllowed: @MainActor () -> Void
    @ObservationIgnored private let observesSystem: Bool

    // MARK: Working state

    /// A tap that exists, with what the watchdog needs to judge it.
    @MainActor private final class LiveTap {
        let app: App
        let handle: any ShapingTapHandle
        var objectIDs: [UInt32]
        var lastBeat: Int64
        var lastBeatTime: TimeInterval
        var lastFrames: Int64
        var lastZeroFrames: Int64
        var zeroRun: Int64 = 0

        init(app: App, handle: any ShapingTapHandle, objectIDs: [UInt32], at time: TimeInterval) {
            self.app = app
            self.handle = handle
            self.objectIDs = objectIDs
            let meter = handle.meter
            lastBeat = meter.callbacks
            lastBeatTime = time
            lastFrames = meter.frames
            lastZeroFrames = meter.zeroFrames
        }
    }

    @MainActor private final class ProbeRun {
        let app: App
        let handle: any ShapingProbeHandle
        let startedAt: TimeInterval
        let maxSeconds: TimeInterval
        var timer: EqualiserTimer?

        init(app: App, handle: any ShapingProbeHandle, startedAt: TimeInterval, maxSeconds: TimeInterval) {
            self.app = app
            self.handle = handle
            self.startedAt = startedAt
            self.maxSeconds = maxSeconds
        }
    }

    @ObservationIgnored private var book: AppSoundBook
    @ObservationIgnored private var lastReading = EqualiserReading()
    @ObservationIgnored private var lastGroups: [EqualiserProcessGroup] = []
    @ObservationIgnored private var lastTargets: [Life.Target] = []
    @ObservationIgnored private var taps: [String: LiveTap] = [:]
    @ObservationIgnored private var probe: ProbeRun?
    @ObservationIgnored private var rebuildTimers: [String: EqualiserTimer] = [:]
    @ObservationIgnored private var idleTimers: [String: EqualiserTimer] = [:]
    @ObservationIgnored private var retargetChecks: [String: EqualiserTimer] = [:]
    @ObservationIgnored private var watchdog: EqualiserTimer?
    @ObservationIgnored private var recheckTimer: EqualiserTimer?
    @ObservationIgnored private var wakeTimer: EqualiserTimer?
    @ObservationIgnored private var backoff = RebuildBackoff()
    @ObservationIgnored private var unsupportedReason: String?
    @ObservationIgnored private var asleep = false
    @ObservationIgnored private var otherShaper = false
    @ObservationIgnored private var hasBuiltAny = false
    @ObservationIgnored private var confirmedUnreadable = Set<Int32>()
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var captureGeneration = 0
    @ObservationIgnored private var pending: [Life.Event] = []
    @ObservationIgnored private var draining = false

    init(
        defaults: UserDefaults,
        factory: any ShapingTapFactory,
        monitor: any EqualiserMonitoring,
        claim: any EqualiserClaiming,
        scheduler: any EqualiserScheduling,
        ownBundleID: String,
        ownPID: Int32,
        now: @escaping () -> Date = Date.init,
        zeusCaptures: @escaping @MainActor () -> Bool = { false },
        onProvenAllowed: @escaping @MainActor () -> Void = {},
        observesSystem: Bool = false
    ) {
        self.defaults = defaults
        self.factory = factory
        self.monitor = monitor
        self.claim = claim
        self.scheduler = scheduler
        self.ownBundleID = ownBundleID
        self.ownPID = ownPID
        self.now = now
        self.zeusCaptures = zeusCaptures
        self.onProvenAllowed = onProvenAllowed
        self.observesSystem = observesSystem

        let stored = defaults.data(forKey: AppSoundBook.storageKey)
        let decoded = AppSoundBook.decode(stored)
        book = decoded.book
        if decoded.failed, let stored {
            savedSettingsUnreadable = true
            // The raw data is copied before any save, and an existing copy is never replaced.
            if defaults.data(forKey: AppSoundBook.unreadableKey) == nil {
                defaults.set(stored, forKey: AppSoundBook.unreadableKey)
            }
        }
        status = EqualiserStatus(
            line: EqualiserStatusText.line(for: .off),
            symbol: EqualiserStatusText.symbol(for: .off),
            rows: EqualiserListRules.rows(groups: [], book: decoded.book, exclusions: [:]))
    }

    // MARK: EqualiserControlling

    func setSwitch(_ on: Bool) {
        if on { switchOn() } else { switchOff() }
    }

    func update(_ settings: AppSoundSettings) {
        var entry = settings
        entry.lastUsed = now()
        if book.add(entry) == .full {
            message = AppSoundBook.fullMessage
            return
        }
        message = nil
        persist()
        bookChanged()
    }

    func forget(bundleID: String) {
        book.remove(bundleID: bundleID)
        persist()
        bookChanged()
    }

    func tryAgain() {
        guard case .stopped = state else { return }
        resetRun()
        otherShaper = !claim.take()
        send(.switchedOn(personAsked: true, makeSnapshot()))
    }

    // MARK: Launch and quit

    /// At launch, before anything is switched on: destroys aggregates a crashed run left behind and notes whether the
    /// last run stopped while shaping. Reads and destroys only; nothing here can raise a prompt.
    func launch() {
        _ = factory.sweepLeftovers()
        if defaults.object(forKey: Self.shapingSinceKey) != nil {
            launchNotice = Self.launchNoticeText
            defaults.removeObject(forKey: Self.shapingSinceKey)
        }
    }

    func acknowledgeLaunchNotice() {
        launchNotice = nil
    }

    /// Quit: every tap destroyed, every listener and timer removed, the claim released.
    func shutdown() {
        switchOff()
    }

    // MARK: Switching

    private func switchOn() {
        guard state == .off else { return }
        resetRun()
        otherShaper = !claim.take()
        monitor.onEvent = { [weak self] event in self?.monitorFired(event) }
        monitor.start()
        installSystemObservers()
        startCaptureObservation()
        send(.switchedOn(personAsked: true, makeSnapshot()))
    }

    private func switchOff() {
        send(.switchedOff)
        monitor.stop()
        monitor.onEvent = nil
        removeSystemObservers()
        captureGeneration += 1
        claim.release()
        cancelEveryTimer()
        asleep = false
        otherShaper = false
        confirmedUnreadable = []
        lastReading = EqualiserReading()
        lastGroups = []
        lastTargets = []
        updateMarker()
        refreshStatus()
    }

    private func resetRun() {
        backoff = RebuildBackoff()
        unsupportedReason = nil
        hasBuiltAny = false
        confirmedUnreadable = []
    }

    // MARK: Events in

    private func monitorFired(_ event: EqualiserMonitorEvent) {
        guard state != .off else { return }
        switch event {
        case .processes:
            send(.processesChanged(makeSnapshot()))
            checkHelpers()
        case .output:
            unsupportedReason = nil
            send(.outputChanged(makeSnapshot()))
        case .format:
            unsupportedReason = nil
            send(.formatChanged(makeSnapshot()))
        case .deviceGone:
            unsupportedReason = nil
            send(.deviceGone(makeSnapshot()))
        }
    }

    func systemWillSleep() {
        guard state != .off else { return }
        wakeTimer?.cancel()
        wakeTimer = nil
        asleep = true
        send(.willSleep)
    }

    func systemDidWake() {
        guard state != .off, asleep else { return }
        wakeTimer?.cancel()
        wakeTimer = scheduler.after(Self.wakeDelaySeconds) { [weak self] in self?.wakeDue() }
    }

    private func wakeDue() {
        wakeTimer = nil
        guard state != .off else { return }
        asleep = false
        send(.didWake(makeSnapshot()))
    }

    /// Zeus began or stopped recording or captioning system sound. Called by the observation below.
    func zeusCaptureMayHaveChanged() {
        guard state != .off else { return }
        send(.zeusCaptureChanged(makeSnapshot()))
    }

    private func startCaptureObservation() {
        captureGeneration += 1
        observeCapture(captureGeneration)
    }

    private func observeCapture(_ generation: Int) {
        let read = zeusCaptures
        withObservationTracking {
            _ = read()
        } onChange: { [weak self] in
            // The change notice arrives before the value changes, so read it on the next main turn.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.captureChanged(generation) }
            }
        }
    }

    private func captureChanged(_ generation: Int) {
        guard generation == captureGeneration, state != .off else { return }
        observeCapture(generation)
        zeusCaptureMayHaveChanged()
    }

    private func installSystemObservers() {
        guard observesSystem, systemObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        systemObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemWillSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemDidWake() }
            },
        ]
    }

    private func removeSystemObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in systemObservers { center.removeObserver(observer) }
        systemObservers = []
    }

    // MARK: Reading the world

    private func makeSnapshot() -> Life.Snapshot {
        snapshot(from: monitor.read())
    }

    private func snapshot(from reading: EqualiserReading) -> Life.Snapshot {
        lastReading = reading
        if otherShaper { otherShaper = !claim.take() }
        let groups = EqualiserPolicy.groups(
            reading.processes, runningAppBundleIDs: reading.runningAppBundleIDs, ownPID: ownPID)
        lastGroups = groups
        lastTargets = EqualiserPolicy.targets(
            groups, names: reading.names, book: book, ownBundleID: ownBundleID,
            defaultOutputUID: reading.output?.uid ?? "")
        let pause = EqualiserPolicy.pauseReason(
            callRecording: callRecording(reading),
            zeusCaptures: zeusCaptures(),
            otherShaper: otherShaper,
            asleep: asleep,
            format: formatVerdict(reading))
        refreshStatus()
        return Life.Snapshot(targets: lastTargets, pause: pause)
    }

    private func formatVerdict(_ reading: EqualiserReading) -> EqualiserFormat.Verdict {
        if let unsupportedReason { return .unsupported(reason: unsupportedReason) }
        guard let output = reading.output else { return .unsupported(reason: "there is no output") }
        // The tap is a stereo mixdown at the output's rate; the real tap is checked again when it is built.
        let tap = EqualiserStreamFormat.float32(sampleRate: output.format.sampleRate, channelCount: 2)
        return EqualiserFormat.verdict(tap: tap, output: output.format, outputIsAggregate: output.isAggregate)
    }

    /// A call app with its input running pauses everything. An input that cannot be read counts only when it is still
    /// unreadable a moment later with the process alive.
    private func callRecording(_ reading: EqualiserReading) -> Bool {
        if EqualiserPolicy.callRecording(reading.processes, ownPID: ownPID) { return true }
        let candidates = Set(EqualiserPolicy.unreadableCallCandidates(reading.processes, ownPID: ownPID).map(\.pid))
        confirmedUnreadable.formIntersection(candidates)
        if recheckTimer == nil, candidates.contains(where: { !confirmedUnreadable.contains($0) }) {
            recheckTimer = scheduler.after(EqualiserPolicy.unreadableRecheckDelay) { [weak self] in
                self?.recheck(candidates)
            }
        }
        return !confirmedUnreadable.isEmpty
    }

    private func recheck(_ pids: Set<Int32>) {
        recheckTimer = nil
        guard state != .off else { return }
        let reading = monitor.read()
        var confirmed = false
        for pid in pids {
            guard let again = reading.processes.first(where: { $0.pid == pid }) else { continue }
            if EqualiserPolicy.unreadableCounts(
                firstRead: nil, reRead: again.runningInput, pidAlive: monitor.pidIsAlive(pid)) {
                confirmedUnreadable.insert(pid)
                confirmed = true
            }
        }
        if confirmed { send(.callRecordingChanged(snapshot(from: reading))) }
    }

    private func refreshStatus() {
        let groups = EqualiserPolicy.playingGroups(lastGroups, names: lastReading.names)
        let exclusions = EqualiserPolicy.exclusions(
            lastGroups, ownBundleID: ownBundleID, defaultOutputUID: lastReading.output?.uid ?? "")
        let next = EqualiserStatus(
            line: EqualiserStatusText.line(for: state),
            symbol: EqualiserStatusText.symbol(for: state),
            rows: EqualiserListRules.rows(groups: groups, book: book, exclusions: exclusions))
        if next != status { status = next }
    }

    // MARK: The reducer loop

    /// Events that arise while effects run (a failed build, a stall) wait their turn, so an effect list is never
    /// interleaved with the reduction of a later event.
    private func send(_ event: Life.Event) {
        pending.append(event)
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while !pending.isEmpty {
            let next = pending.removeFirst()
            let (newState, effects) = Life.reduce(state, next)
            state = newState
            apply(effects)
            reconcileIdleTimers()
            refreshStatus()
        }
    }

    private func apply(_ effects: [Life.Effect]) {
        for effect in effects {
            switch effect {
            case .probe(let app, let maxSeconds): startProbe(app, maxSeconds: maxSeconds)
            case .buildTap(let app): buildTap(app)
            case .retarget(let app): retarget(app)
            case .destroyTap(let app): destroy(app)
            case .destroyAll: destroyAll()
            case .scheduleRebuild(let app, let delay): scheduleRebuild(app, after: delay)
            case .startWatchdog: startWatchdog()
            case .stopWatchdog: stopWatchdog()
            case .recordAllowed: onProvenAllowed()
            case .post(let app, let parameters): taps[app.bundleID]?.handle.post(parameters)
            }
        }
    }

    // MARK: Probes

    private func request(for app: App) -> ShapingRequest? {
        guard let group = lastGroups.first(where: { $0.bundleID == app.bundleID }),
              let output = lastReading.output else { return nil }
        return ShapingRequest(
            group: group, displayName: app.displayName, output: output,
            parameters: book.parameters(for: app.bundleID) ?? .flat)
    }

    private func startProbe(_ app: App, maxSeconds: TimeInterval) {
        guard let request = request(for: app) else {
            send(.probeResult(app, .inconclusive, seconds: 0, makeSnapshot()))
            return
        }
        do {
            let handle = try factory.makeProbe(request)
            hasBuiltAny = true
            let run = ProbeRun(app: app, handle: handle, startedAt: scheduler.now, maxSeconds: maxSeconds)
            probe = run
            run.timer = scheduler.every(Self.probePollSeconds) { [weak self] in self?.pollProbe() }
        } catch let failure as ShapingFailure {
            probeFailed(app, failure)
        } catch {
            probeFailed(app, .system(stage: "probe", status: -1))
        }
    }

    private func probeFailed(_ app: App, _ failure: ShapingFailure) {
        if case .unsupported(let reason) = failure {
            markUnsupported(reason)
        } else if failure.isEngineWide, !hasBuiltAny {
            send(.startFailed(status: failure.status))
        } else {
            send(.probeResult(app, .inconclusive, seconds: 0, makeSnapshot()))
        }
    }

    private func pollProbe() {
        guard let run = probe else { return }
        let meter = run.handle.meter
        let elapsed = scheduler.now - run.startedAt
        if meter.frames - meter.zeroFrames > 0 {
            finishProbe(.heard, elapsed: elapsed)
        } else if elapsed >= run.maxSeconds {
            finishProbe(meter.frames > 0 ? .silent : .inconclusive, elapsed: elapsed)
        }
    }

    private func finishProbe(_ verdict: EqualiserProbeVerdict, elapsed: TimeInterval) {
        guard let run = probe else { return }
        run.timer?.cancel()
        run.handle.stop()
        probe = nil
        send(.probeResult(run.app, verdict, seconds: elapsed, makeSnapshot()))
    }

    // MARK: Taps

    private func buildTap(_ app: App) {
        let key = app.bundleID
        guard taps[key] == nil, let request = request(for: app) else { return }
        do {
            let handle = try factory.makeTap(request)
            hasBuiltAny = true
            taps[key] = LiveTap(app: app, handle: handle, objectIDs: request.group.objectIDs, at: scheduler.now)
            updateMarker()
        } catch let failure as ShapingFailure {
            tapFailed(app, failure)
        } catch {
            tapFailed(app, .system(stage: "build", status: -1))
        }
    }

    private func tapFailed(_ app: App, _ failure: ShapingFailure) {
        if case .unsupported(let reason) = failure {
            markUnsupported(reason)
            return
        }
        let failures = backoff.recordFailure(bundleID: app.bundleID, at: scheduler.now)
        send(.buildFailed(app, status: failure.status, failures: failures))
    }

    /// The real tap or output cannot be rendered. Nothing is muted; the engine pauses until the output changes.
    private func markUnsupported(_ reason: String) {
        unsupportedReason = reason
        send(.formatChanged(makeSnapshot()))
    }

    private func retarget(_ app: App) {
        let key = app.bundleID
        guard let live = taps[key], let group = lastGroups.first(where: { $0.bundleID == key }) else { return }
        guard live.handle.retarget(objectIDs: group.objectIDs) else {
            send(.retargetFailed(app))
            return
        }
        live.objectIDs = group.objectIDs
        let baseline = live.handle.meter.callbacks
        retargetChecks[key]?.cancel()
        retargetChecks[key] = scheduler.after(Self.retargetCheckSeconds) { [weak self] in
            self?.retargetChecked(app, baseline: baseline)
        }
    }

    /// Two seconds after a process list write: a tap that heard nothing since is rebuilt.
    private func retargetChecked(_ app: App, baseline: Int64) {
        retargetChecks[app.bundleID] = nil
        guard let live = taps[app.bundleID] else { return }
        let playing = lastTargets.first { $0.app.bundleID == app.bundleID }?.isPlaying ?? false
        if playing, live.handle.meter.callbacks == baseline { send(.retargetFailed(app)) }
    }

    private func destroy(_ app: App) {
        let key = app.bundleID
        rebuildTimers.removeValue(forKey: key)?.cancel()
        idleTimers.removeValue(forKey: key)?.cancel()
        retargetChecks.removeValue(forKey: key)?.cancel()
        if let live = taps.removeValue(forKey: key) { live.handle.stop() }
        if let run = probe, run.app.bundleID == key {
            run.timer?.cancel()
            run.handle.stop()
            probe = nil
        }
        updateMarker()
    }

    private func destroyAll() {
        for timer in rebuildTimers.values { timer.cancel() }
        for timer in idleTimers.values { timer.cancel() }
        for timer in retargetChecks.values { timer.cancel() }
        rebuildTimers = [:]
        idleTimers = [:]
        retargetChecks = [:]
        for key in taps.keys.sorted() { taps[key]?.handle.stop() }
        taps = [:]
        if let run = probe {
            run.timer?.cancel()
            run.handle.stop()
            probe = nil
        }
        updateMarker()
    }

    private func scheduleRebuild(_ app: App, after delay: TimeInterval) {
        let key = app.bundleID
        rebuildTimers[key]?.cancel()
        rebuildTimers[key] = scheduler.after(delay) { [weak self] in self?.rebuildDue(app) }
    }

    private func rebuildDue(_ app: App) {
        rebuildTimers[app.bundleID] = nil
        guard state != .off, runningApps().contains(app), taps[app.bundleID] == nil else { return }
        _ = makeSnapshot()
        guard lastTargets.contains(where: { $0.app.bundleID == app.bundleID }) else { return }
        buildTap(app)
    }

    private func runningApps() -> [App] {
        switch state {
        case .running(let apps): return apps
        case .probing(_, _, let running): return running
        default: return []
        }
    }

    /// A helper process joined an app that has a tap: its process list is written again.
    private func checkHelpers() {
        for key in taps.keys.sorted() {
            guard let live = taps[key], let group = lastGroups.first(where: { $0.bundleID == key }) else { continue }
            if !Set(group.objectIDs).isSubset(of: Set(live.objectIDs)) { send(.helperJoined(live.app)) }
        }
    }

    // MARK: Idle, watchdog

    /// A tap whose app stopped playing is removed 30 seconds later; playing again keeps it.
    private func reconcileIdleTimers() {
        for key in taps.keys.sorted() {
            let playing = lastTargets.first { $0.app.bundleID == key }?.isPlaying ?? false
            if playing {
                idleTimers.removeValue(forKey: key)?.cancel()
            } else if idleTimers[key] == nil, let live = taps[key] {
                let app = live.app
                idleTimers[key] = scheduler.after(Life.idleSeconds) { [weak self] in
                    self?.idleTimers[key] = nil
                    self?.send(.idleExpired(app))
                }
            }
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = scheduler.every(Self.watchdogSeconds) { [weak self] in self?.tick() }
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    /// One second of the watchdog: a tap that stopped calling back, or heard only exact zeros while its app plays.
    private func tick() {
        let time = scheduler.now
        for key in taps.keys.sorted() {
            guard let live = taps[key] else { continue }
            let playing = lastTargets.first { $0.app.bundleID == key }?.isPlaying ?? false
            let meter = live.handle.meter

            let missed = EqualiserWatchdog.missed(
                lastBeatCount: live.lastBeat, currentCount: meter.callbacks,
                elapsed: time - live.lastBeatTime, appPlaying: playing)
            if meter.callbacks != live.lastBeat {
                live.lastBeat = meter.callbacks
                live.lastBeatTime = time
            }
            let frames = meter.frames - live.lastFrames
            let zeros = meter.zeroFrames - live.lastZeroFrames
            live.lastFrames = meter.frames
            live.lastZeroFrames = meter.zeroFrames
            if !playing {
                live.zeroRun = 0
            } else if frames > 0 {
                live.zeroRun = zeros == frames ? live.zeroRun + frames : 0
            }

            if missed {
                let failures = backoff.recordFailure(bundleID: key, at: time)
                send(.heartbeatMissed(live.app, failures: failures))
            } else if ZeroWatch.verdict(
                zeroFrames: live.zeroRun, sampleRate: live.handle.sampleRate, playing: playing, muted: true) == .stalled {
                live.zeroRun = 0
                send(.zerosWhilePlaying(live.app))
            }
        }
    }

    // MARK: Store, marker, timers

    private func persist() {
        do {
            defaults.set(try book.encode(), forKey: AppSoundBook.storageKey)
        } catch {
            message = "Saved settings could not be written."
        }
    }

    private func bookChanged() {
        if state == .off {
            refreshStatus()
        } else {
            send(.settingsChanged(makeSnapshot()))
        }
    }

    /// Written when the first muted tap exists, removed when none does.
    private func updateMarker() {
        if taps.isEmpty {
            if defaults.object(forKey: Self.shapingSinceKey) != nil { defaults.removeObject(forKey: Self.shapingSinceKey) }
        } else if defaults.object(forKey: Self.shapingSinceKey) == nil {
            defaults.set(now().timeIntervalSince1970, forKey: Self.shapingSinceKey)
        }
    }

    private func cancelEveryTimer() {
        for timer in rebuildTimers.values { timer.cancel() }
        for timer in idleTimers.values { timer.cancel() }
        for timer in retargetChecks.values { timer.cancel() }
        rebuildTimers = [:]
        idleTimers = [:]
        retargetChecks = [:]
        watchdog?.cancel()
        watchdog = nil
        recheckTimer?.cancel()
        recheckTimer = nil
        wakeTimer?.cancel()
        wakeTimer = nil
        probe?.timer?.cancel()
        probe = nil
        pending = []
    }
}
