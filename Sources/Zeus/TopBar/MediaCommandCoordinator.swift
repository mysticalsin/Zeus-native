import Foundation
import ZeusCore
#if canImport(AppKit)
import AppKit
#endif
#if canImport(os)
import os
#endif

/// One shot for the open callback and the give-up sleep. The first value wins.
private final class LaunchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var value: Bool?

    func firstValue() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let value {
                lock.unlock()
                continuation.resume(returning: value)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func resolve(_ opened: Bool) {
        lock.lock()
        if value != nil {
            lock.unlock()
            return
        }
        value = opened
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        // Resume off this turn. The waiter is on the main actor, and resuming it inline
        // from the open callback deadlocks that actor.
        if let continuation {
            Task.detached { continuation.resume(returning: opened) }
        }
    }
}

enum MediaClockMath {
    /// Seconds for the router. Snapped to 1/128 s, a fraction Double can subtract exactly,
    /// so a full debounce window does not come back a hair under `debounceWindow`.
    static func seconds(from duration: Duration) -> Double {
        let parts = duration.components
        let raw = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        let quantum = 1.0 / 128.0
        return (raw / quantum).rounded() * quantum
    }
}

/// Monotonic instants for launch deadlines. `wall` can jump without moving `now`.
/// Production reads `ContinuousClock`. A deadline never subtracts `wall`.
protocol MediaCommandClock: Sendable {
    var now: ContinuousClock.Instant { get }
    var wall: Date { get }
    func sleep(for duration: Duration) async throws
}

struct MediaSystemCommandClock: MediaCommandClock {
    var now: ContinuousClock.Instant { ContinuousClock.now }
    var wall: Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration, clock: ContinuousClock())
    }
}

/// Starts an open and reports whether the process has finished launching.
/// The driver owns the budget, so this does not sleep.
@MainActor
protocol MediaPlayerLaunching: AnyObject {
    func startOpen(bundleID: String, activates: Bool, done: @escaping @Sendable (Bool) -> Void)
    func isFinishedLaunching(bundleID: String) -> Bool
}

/// Hands a command to the player and reads the real sample back.
@MainActor
protocol MediaCommandTransport: AnyObject {
    func deliver(_ command: MediaControlCommand, route: MediaCommandRoute) async -> MediaCommandDelivery
    func readBack(_ route: MediaCommandRoute) async
}

/// The transport router plus the launch wait. Deadlines use `clock.now`.
/// The give-up sleep is cancelled when the open callback arrives, when a later command
/// takes its place, and when `stop` runs. A late open after `stop` does not play.
@MainActor
final class MediaCommandDriver {
    private let clock: any MediaCommandClock
    private let opener: any MediaPlayerLaunching
    private let transport: any MediaCommandTransport
    private let origin: ContinuousClock.Instant
    private var router = MediaCommandRouter()
    private var generation = 0
    private var gate: LaunchGate?
    private var launchTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var settled = 0
    private var settleWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var launchFinished = false
    private var launchWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var sent: [MediaControlCommand] = []
    private(set) var pendingSleep: Task<Void, Never>?
    var onLog: (@MainActor (String) -> Void)?
    var onState: (@MainActor (MediaCommandState) -> Void)?
    var onRecovery: (@MainActor () -> Void)?

    var state: MediaCommandState { router.state }

    init(clock: any MediaCommandClock, opener: any MediaPlayerLaunching, transport: any MediaCommandTransport) {
        self.clock = clock
        self.opener = opener
        self.transport = transport
        self.origin = clock.now
    }

    func resync(_ sample: MediaNowPlayingSample?) {
        _ = try? router.reduce(.info(sample), now: monotonicNow())
        publish()
    }

    func press(_ command: MediaControlCommand) {
        let effects: [MediaCommandEffect]
        do {
            effects = try router.reduce(.press(command), now: monotonicNow())
        } catch let rejection as MediaCommandRejection {
            onLog?("command \(Self.word(command)) rejected \(Self.word(rejection.reason))")
            return
        } catch {
            return
        }
        if effects.isEmpty, case .noSource = router.state {
            onLog?("command \(Self.word(command)) nosource")
            return
        }
        if !effects.isEmpty { cancelPendingSleep() }
        publish()
        perform(effects)
    }

    func recover() {
        let effects: [MediaCommandEffect]
        do {
            effects = try router.reduce(.recover, now: monotonicNow())
        } catch {
            return
        }
        publish()
        perform(effects)
    }

    func stop() {
        generation += 1
        cancelPendingSleep()
        commandTask?.cancel()
        gate?.resolve(false)
        launchTask?.cancel()
    }

    /// Completes once the command that was just started has armed its sleep, or has finished without one.
    func waitUntilParked() async {
        if pendingSleep != nil { return }
        let mark = settled
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if pendingSleep != nil || settled > mark {
                continuation.resume()
                return
            }
            settleWaiters.append((mark, continuation))
        }
    }

    func waitUntilLaunchSettled() async {
        if launchFinished { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if launchFinished {
                continuation.resume()
                return
            }
            launchWaiters.append(continuation)
        }
    }

    private func noteLaunchFinished() {
        launchFinished = true
        let waiters = launchWaiters
        launchWaiters.removeAll()
        for waiter in waiters {
            Task.detached { waiter.resume() }
        }
    }

    private func monotonicNow() -> Double {
        MediaClockMath.seconds(from: clock.now - origin)
    }

    private func publish() {
        onState?(router.state)
    }

    private func cancelPendingSleep() {
        pendingSleep?.cancel()
        pendingSleep = nil
    }

    private func noteSettled() {
        settled += 1
        var stay: [(Int, CheckedContinuation<Void, Never>)] = []
        var ready: [CheckedContinuation<Void, Never>] = []
        for (mark, waiter) in settleWaiters {
            if settled > mark {
                ready.append(waiter)
            } else {
                stay.append((mark, waiter))
            }
        }
        settleWaiters = stay
        for waiter in ready {
            Task.detached { waiter.resume() }
        }
    }

    private func perform(_ effects: [MediaCommandEffect]) {
        var send: (MediaControlCommand, MediaCommandRoute)?
        var launch: (bundleID: String, activates: Bool)?
        var after = MediaCommandRouter.resyncDelay
        for effect in effects {
            switch effect {
            case .send(let command, let route):
                send = (command, route)
            case .resync(_, let delay):
                after = delay
            case .openRecovery:
                onLog?("recovery opened")
                onRecovery?()
            case .launch(let bundleID, let activates):
                launch = (bundleID, activates)
            }
        }
        if let launch {
            launchPlayer(bundleID: launch.bundleID, activates: launch.activates)
            return
        }
        guard let (command, route) = send else { return }
        generation += 1
        let token = generation
        commandTask?.cancel()
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard token == self.generation, !Task.isCancelled else {
                self.noteSettled()
                return
            }
            self.sent.append(command)
            let result = await self.transport.deliver(command, route: route)
            guard token == self.generation, !Task.isCancelled else {
                self.noteSettled()
                return
            }
            self.apply(.result(result))
            guard result == .accepted else {
                self.noteSettled()
                return
            }
            let sleep = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await self.clock.sleep(for: .seconds(after))
            }
            self.pendingSleep?.cancel()
            self.pendingSleep = sleep
            self.noteSettled()
            await sleep.value
            guard token == self.generation, !Task.isCancelled, !sleep.isCancelled else { return }
            await self.transport.readBack(route)
        }
    }

    /// Opens the player behind Zeus, then sends play if it is ready inside `launchTimeout`.
    private func launchPlayer(bundleID: String, activates: Bool) {
        generation += 1
        let token = generation
        let startedInstant = clock.now
        let started = monotonicNow()
        let gate = LaunchGate()
        self.gate = gate
        launchFinished = false
        onLog?("command play launched bundle=\(bundleID)")
        pendingSleep = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.clock.sleep(for: .seconds(MediaCommandRouter.launchTimeout + 1))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            gate.resolve(false)
        }
        opener.startOpen(bundleID: bundleID, activates: activates) { [weak self] opened in
            Task { @MainActor in
                guard let self else { return }
                self.pendingSleep?.cancel()
                gate.resolve(opened)
            }
        }
        launchTask = Task { @MainActor [weak self] in
            await self?.finishLaunch(gate: gate, token: token, bundleID: bundleID,
                                     startedInstant: startedInstant, started: started)
            self?.noteLaunchFinished()
        }
    }

    private func finishLaunch(gate: LaunchGate, token: Int, bundleID: String,
                              startedInstant: ContinuousClock.Instant, started: Double) async {
        let opened = await gate.firstValue()
        guard token == generation, !Task.isCancelled else { return }
        let elapsed = MediaClockMath.seconds(from: clock.now - startedInstant)
        let ready: Bool
        if opened, elapsed <= MediaCommandRouter.launchTimeout {
            ready = await pollReady(bundleID: bundleID, startedInstant: startedInstant)
        } else {
            ready = false
        }
        guard token == generation, !Task.isCancelled else { return }
        let now = monotonicNow()
        let event: MediaCommandEvent
        let when: Double
        if ready, MediaCommandRouter.launchAccepted(startedAt: started, now: now) {
            event = .sourceReady
            when = now
        } else {
            event = .launchClock
            when = started + MediaCommandRouter.launchTimeout + 1
        }
        let effects = (try? router.reduce(event, now: when)) ?? []
        if case .failed(.launchFailed) = router.state {
            onLog?("command play launchFailed")
        }
        publish()
        perform(effects)
    }

    /// Polls until the player has finished launching, or the monotonic budget has passed.
    /// The gap stays 50 milliseconds. The budget stays `launchTimeout`.
    private func pollReady(bundleID: String, startedInstant: ContinuousClock.Instant) async -> Bool {
        while MediaClockMath.seconds(from: clock.now - startedInstant) <= MediaCommandRouter.launchTimeout {
            if Task.isCancelled { return false }
            if opener.isFinishedLaunching(bundleID: bundleID) { return true }
            do {
                try await clock.sleep(for: .milliseconds(50))
            } catch {
                return false
            }
        }
        return false
    }

    private func apply(_ event: MediaCommandEvent) {
        let pending = Self.pending(router)
        _ = try? router.reduce(event, now: monotonicNow())
        if case .result(let delivery) = event, let pending {
            switch delivery {
            case .accepted:
                onLog?("command \(pending.name) accepted\(pending.target)")
            case .permissionDenied:
                onLog?("command \(pending.name) permissionDenied")
            case .unavailable:
                onLog?("command \(pending.name) unavailable")
            case .failed:
                onLog?("command \(pending.name) failed")
            }
        }
        publish()
    }

    private static func pending(_ router: MediaCommandRouter) -> (name: String, target: String)? {
        guard case .commandPending(let command) = router.state else { return nil }
        let target: String
        switch router.route?.endpoint {
        case .scriptedPlayer(let bundleID): target = " bundle=\(bundleID)"
        case .browser: target = " browser"
        case nil: target = ""
        }
        return (word(command), target)
    }

    private static func word(_ command: MediaControlCommand) -> String {
        switch command {
        case .play: "play"
        case .pause: "pause"
        case .next: "next"
        case .previous: "previous"
        case .seek: "seek"
        }
    }

    private static func word(_ reason: MediaCommandRejection.Reason) -> String {
        switch reason {
        case .illegalTransition: "illegalTransition"
        case .duplicate: "duplicate"
        case .unsupported: "unsupported"
        case .inFlight: "inFlight"
        case .blocked: "blocked"
        }
    }
}

#if canImport(AppKit)
private enum MediaCommandLog {
    #if canImport(os)
    static let logger = Logger(subsystem: "app.zeus.mac", category: "media-playback")

    static func write(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
    #else
    static func write(_ message: String) {}
    #endif
}

/// Runs the home and music transport through `MediaCommandRouter`.
///
/// A scripted player is told with an Apple Event, by bundle id, through the existing out-of-process
/// script runner. A browser tab uses the feed already attached to the hub. `MPRemoteCommandCenter`
/// cannot control another app, so it is not used. The private media-remote gate is off and fails closed,
/// so that path is never taken.
@MainActor
final class MediaCommandCoordinator {
    private let model: TopBarModel
    private let driver: MediaCommandDriver

    init(model: TopBarModel, hub: NowPlayingHub, feed: MusicPlayerFeed) {
        self.model = model
        let driver = MediaCommandDriver(
            clock: MediaSystemCommandClock(),
            opener: WorkspacePlayerLaunch(),
            transport: FeedMediaTransport(model: model, hub: hub, feed: feed))
        driver.onLog = { MediaCommandLog.write($0) }
        driver.onState = { [weak model] state in
            guard let model else { return }
            if model.mediaPlayback != state { model.mediaPlayback = state }
        }
        driver.onRecovery = { [weak model] in model?.openPermissions() }
        self.driver = driver
    }

    func start() {
        model.homeMediaPress = { [weak self] in self?.driver.press($0) }
        model.mediaRecovery = { [weak self] in self?.driver.recover() }
        model.resyncHomeMedia = { [weak self] in self?.driver.resync(self?.sample($0)) }
        driver.resync(sample(model.nowPlaying))
    }

    func stop() {
        driver.stop()
        model.homeMediaPress = { _ in }
        model.mediaRecovery = {}
        model.resyncHomeMedia = { _ in }
    }

    private func sample(_ playing: NowPlaying?) -> MediaNowPlayingSample? {
        guard let playing else { return nil }
        let caps = playing.capabilities
        let route: MediaCommandRoute
        switch playing.source {
        case .player(let player):
            route = MediaCommandRoute(endpoint: .scriptedPlayer(bundleID: player.bundleID),
                                       canSkip: caps.contains(.next) && caps.contains(.previous),
                                       canSeek: caps.contains(.seek))
        case .browser(let key):
            route = MediaCommandRoute(endpoint: .browser(tabID: key.tabID, documentID: key.documentID),
                                       canSkip: false,
                                       canSeek: caps.contains(.seek))
        }
        return MediaNowPlayingSample(isPlaying: playing.isPlaying, position: playing.elapsed(),
                                     duration: playing.duration, route: route)
    }
}

@MainActor
private final class WorkspacePlayerLaunch: MediaPlayerLaunching {
    func startOpen(bundleID: String, activates: Bool, done: @escaping @Sendable (Bool) -> Void) {
        guard NowPlaying.Player(bundleID: bundleID) != nil,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            done(false)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            done(app != nil && error == nil)
        }
    }

    func isFinishedLaunching(bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.isFinishedLaunching == true
    }
}

@MainActor
private final class FeedMediaTransport: MediaCommandTransport {
    private let model: TopBarModel
    private let hub: NowPlayingHub
    private let feed: MusicPlayerFeed

    init(model: TopBarModel, hub: NowPlayingHub, feed: MusicPlayerFeed) {
        self.model = model
        self.hub = hub
        self.feed = feed
    }

    func deliver(_ command: MediaControlCommand, route: MediaCommandRoute) async -> MediaCommandDelivery {
        // MediaRemoteCommandGate is off and fails closed. This path does not call it.
        switch route.endpoint {
        case .scriptedPlayer(let bundleID):
            guard let player = NowPlaying.Player(bundleID: bundleID) else { return .unavailable }
            return await feed.deliver(command, to: player)
        case .browser(let tabID, let documentID):
            guard let send = hub.browserCommand,
                  case .browser(let key) = model.nowPlaying?.source,
                  key.tabID == tabID, key.documentID == documentID else { return .unavailable }
            let (kind, seconds) = Self.browserCommand(command)
            send(kind, seconds, key)
            return .accepted
        }
    }

    func readBack(_ route: MediaCommandRoute) async {
        switch route.endpoint {
        case .scriptedPlayer(let bundleID):
            guard let player = NowPlaying.Player(bundleID: bundleID) else { return }
            guard feed.isPlayerRunning(player) else {
                hub.update(.player(player), nil, announce: false)
                return
            }
            if let playing = await feed.readPlayer(player) {
                hub.update(.player(player), playing, announce: false)
            }
        case .browser:
            break
        }
    }

    private static func browserCommand(_ command: MediaControlCommand) -> (MusicCommandKind, Double?) {
        switch command {
        case .play: (.play, nil)
        case .pause: (.pause, nil)
        case .next: (.next, nil)
        case .previous: (.previous, nil)
        case .seek(let seconds): (.seek, seconds)
        }
    }
}
#endif
