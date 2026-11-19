import Foundation

// The lifecycle of per-app shaping as a pure reducer. A state and an event go in; a new state and an ordered list of
// effects come out. The controller reads the world, builds the event, and carries the effects out; nothing here opens
// audio, starts a timer or touches the main thread.
//
// Who sends what. Events that can start or stop a tap carry a `Snapshot`: what the controller has just read, already
// judged by `EqualiserPolicy`. Events about one tap (`heartbeatMissed`, `buildFailed`, `idleExpired` and the others)
// carry the app and, where a count matters, how many failures the controller has seen in the window.

/// What a short listen-only probe heard. The reducer only reads it; the consent rules decide it.
public enum EqualiserProbeVerdict: Sendable, Equatable {
    /// Real sound arrived.
    case heard
    /// Only zeros while the app reported output running.
    case silent
    /// Nothing can be said: the app was not playing for long enough, or the probe was cut short.
    case inconclusive
}

/// The consent rules: what a probe proved, how long it listens and when silence stops shaping. Pure, so the controller
/// only reads counters and carries out the answer.
public enum EqualiserConsent {
    /// The first probe after `notAsked` listens this long, since the owner may still be reading the prompt.
    public static let firstProbeSeconds: TimeInterval = 30

    /// Real sound is `heard`. Only zeros while the app reports output running is `silent`. No frames at all, or zeros
    /// from an app that is not playing, prove nothing.
    public static func verdict(nonZeroFrames: Int64, framesSeen: Int64, appPlaying: Bool) -> EqualiserProbeVerdict {
        if nonZeroFrames > 0 { return .heard }
        return framesSeen > 0 && appPlaying ? .silent : .inconclusive
    }

    /// How long a probe may listen.
    public static func probeSeconds(permission: AudioCapturePermission) -> TimeInterval {
        permission == .notAsked ? firstProbeSeconds : EqualiserLifecycle.probeSeconds
    }

    /// True once this many silent probes in a row, each at least `silentProbeSeconds` long, have been counted.
    public static func stopsAfter(_ countedSilentProbes: Int) -> Bool {
        countedSilentProbes >= EqualiserLifecycle.silentProbesToStop
    }
}

public enum EqualiserLifecycle {
    /// The longest a probe listens.
    public static let probeSeconds: TimeInterval = 5
    /// How long a tap outlives its app's output. The controller starts the timer and sends `idleExpired`.
    public static let idleSeconds: TimeInterval = 30
    /// A silent probe counts toward a stop only when it listened at least this long.
    public static let silentProbeSeconds: TimeInterval = 5
    /// Silent probes in a row that stop shaping.
    public static let silentProbesToStop = 2

    public typealias App = EqualiserPlayingGroup

    /// An app a tap may exist for: saved, not neutral, not excluded. Neutral and excluded apps are never targets, so
    /// nothing below can build a tap for them.
    public struct Target: Sendable, Equatable {
        public let app: App
        public let parameters: EqualiserParameters
        /// False while the app is running but its output has stopped. Its tap stays for `idleSeconds`.
        public let isPlaying: Bool

        public init(app: App, parameters: EqualiserParameters, isPlaying: Bool) {
            self.app = app
            self.parameters = parameters
            self.isPlaying = isPlaying
        }
    }

    /// What the controller has just read. A tap whose app is in neither list is destroyed at once, which is how a quit
    /// app, a neutral app and an app whose switch went off lose their tap.
    public struct Snapshot: Sendable, Equatable {
        public var targets: [Target]
        /// Why every tap must go right now, from `EqualiserPolicy.pauseReason`. Nil when shaping may run.
        public var pause: EqualiserPause?
        /// Where System Audio Recording stands. Only `SpectrumGate.decision` reads it, to decide whether a probe may
        /// start; it never decides whether to mute.
        public var permission: AudioCapturePermission
        /// A person asked: the switch, "Try again", or the owner's own stored switch at launch.
        public var personAsked: Bool

        public init(
            targets: [Target] = [], pause: EqualiserPause? = nil,
            permission: AudioCapturePermission = .allowed, personAsked: Bool = true
        ) {
            self.targets = targets
            self.pause = pause
            self.permission = permission
            self.personAsked = personAsked
        }
    }

    public enum State: Sendable, Equatable {
        case off
        /// On, and no app has played yet, so setup is not finished.
        case waitingForSound
        /// One listen-only probe is out for `app`. `attempt` counts silent probes in a row. `running` are the muted taps
        /// that exist beside it.
        case probing(App, attempt: Int, running: [App])
        /// The apps with a muted tap, possibly none.
        case running([App])
        case paused(EqualiserPause)
        case stopped(EqualiserStop)
    }

    public enum Event: Sendable, Equatable {
        /// The owner's switch. `personAsked` is true for the switch or "Try again", false for a start at launch.
        case switchedOn(personAsked: Bool, Snapshot)
        case switchedOff
        case probeResult(App, EqualiserProbeVerdict, seconds: TimeInterval, Snapshot)
        case processesChanged(Snapshot)
        case outputChanged(Snapshot)
        case formatChanged(Snapshot)
        case deviceGone(Snapshot)
        case willSleep
        case didWake(Snapshot)
        case callRecordingChanged(Snapshot)
        case zeusCaptureChanged(Snapshot)
        case claimLost
        case heartbeatMissed(App, failures: Int)
        case zerosWhilePlaying(App)
        case buildFailed(App, status: Int32, failures: Int)
        /// The engine could not start at all, for a reason that is not one app's: no default output, or the tap call
        /// refused. Stops until "Try again".
        case startFailed(status: Int32)
        case idleExpired(App)
        case helperJoined(App)
        case retargetFailed(App)
        case settingsChanged(Snapshot)
    }

    /// Effects come in the order to carry them out. Destroys always precede builds and probes.
    public enum Effect: Sendable, Equatable {
        /// Listen only, up to `maxSeconds`, and end early on `heard`.
        case probe(App, maxSeconds: TimeInterval)
        /// Build the muted tap, seeded with the app's current parameters.
        case buildTap(App)
        /// Write the live tap's process list again.
        case retarget(App)
        /// Destroy one tap or probe and cancel any rebuild waiting for it.
        case destroyTap(App)
        /// Destroy every tap and probe and cancel every waiting rebuild.
        case destroyAll
        /// Build that app's tap again after the delay, seeded with its current parameters.
        case scheduleRebuild(App, after: TimeInterval)
        /// Start the one-second watchdog, or restart it after taps were rebuilt.
        case startWatchdog
        case stopWatchdog
        /// Sound was heard, so write `allowed`.
        case recordAllowed
        case post(App, EqualiserParameters)
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        // The two switch events work from any state.
        switch event {
        case .switchedOff:
            return (.off, [.destroyAll, .stopWatchdog])
        case .switchedOn(let personAsked, var snapshot):
            snapshot.personAsked = snapshot.personAsked && personAsked
            switch state {
            case .off, .stopped: return begin(snapshot)
            default: return (state, [])
            }
        default:
            break
        }

        // Off and stopped are left only by the switch.
        switch state {
        case .off, .stopped: return (state, [])
        default: break
        }

        switch event {
        case .startFailed(let status):
            return stop(.startFailed(status: status))
        case .willSleep:
            if case .paused(.asleep) = state { return (state, []) }
            return (.paused(.asleep), [.destroyAll, .stopWatchdog])
        case .claimLost:
            if case .paused(.asleep) = state { return (state, []) }
            if case .paused = state { return (.paused(.otherShaper), []) }
            return (.paused(.otherShaper), [.destroyAll, .stopWatchdog])
        default:
            break
        }

        // Asleep ends with the wake and nothing else.
        if case .paused(.asleep) = state {
            if case .didWake(let snapshot) = event {
                return evaluate(state, snapshot, rebuild: false, posts: false)
            }
            return (state, [])
        }

        switch event {
        case .didWake:
            return (state, [])
        case .processesChanged(let snapshot),
             .callRecordingChanged(let snapshot),
             .zeusCaptureChanged(let snapshot):
            return evaluate(state, snapshot, rebuild: false, posts: false)
        case .settingsChanged(let snapshot):
            return evaluate(state, snapshot, rebuild: false, posts: true)
        case .outputChanged(let snapshot),
             .formatChanged(let snapshot),
             .deviceGone(let snapshot):
            return evaluate(state, snapshot, rebuild: true, posts: false)
        case .probeResult(let app, let verdict, let seconds, let snapshot):
            return probeResult(state, app: app, verdict: verdict, seconds: seconds, snapshot: snapshot)
        case .heartbeatMissed(let app, let failures), .buildFailed(let app, _, let failures):
            guard taps(of: state).running.contains(app) else { return (state, []) }
            guard let delay = RebuildBackoff.delay(afterFailures: failures) else {
                return stop(.repeatedFailures(app: app.displayName))
            }
            return (state, [.destroyTap(app), .scheduleRebuild(app, after: delay)])
        case .zerosWhilePlaying(let app):
            return stall(state, app: app)
        case .idleExpired(let app):
            return expire(state, app: app)
        case .helperJoined(let app):
            return taps(of: state).running.contains(app) ? (state, [.retarget(app)]) : (state, [])
        case .retargetFailed(let app):
            return taps(of: state).running.contains(app) ? (state, [.destroyTap(app), .buildTap(app)]) : (state, [])
        case .switchedOn, .switchedOff, .startFailed, .willSleep, .claimLost:
            return (state, [])
        }
    }

    // MARK: Pieces

    private typealias Probe = (app: App, attempt: Int)

    private static func taps(of state: State) -> (running: [App], probing: Probe?) {
        switch state {
        case .running(let apps): return (apps, nil)
        case .probing(let app, let attempt, let running): return (running, (app, attempt))
        default: return ([], nil)
        }
    }

    /// True when setup has not finished: nothing has been built since the switch went on.
    private static func isFresh(_ state: State) -> Bool {
        switch state {
        case .off, .stopped, .waitingForSound: return true
        case .probing(_, _, let running): return running.isEmpty
        case .running, .paused: return false
        }
    }

    private static func stop(_ reason: EqualiserStop) -> (State, [Effect]) {
        (.stopped(reason), [.destroyAll, .stopWatchdog])
    }

    private static func begin(_ snapshot: Snapshot) -> (State, [Effect]) {
        if let pause = snapshot.pause { return (.paused(pause), [.destroyAll, .stopWatchdog]) }
        return settle(
            snapshot, running: [], probing: nil, proven: [], skip: nil, next: nil,
            fresh: true, watchdogWasOn: false, rebuild: false, posts: false, prefix: [])
    }

    /// The common path for every event that carries a snapshot.
    private static func evaluate(
        _ state: State, _ snapshot: Snapshot, rebuild: Bool, posts: Bool
    ) -> (State, [Effect]) {
        if let pause = snapshot.pause {
            if case .paused(pause) = state { return (state, []) }
            if case .paused = state { return (.paused(pause), []) }
            return (.paused(pause), [.destroyAll, .stopWatchdog])
        }
        let current = taps(of: state)
        if rebuild {
            return settle(
                snapshot, running: [], probing: nil, proven: current.running, skip: nil, next: nil,
                fresh: isFresh(state), watchdogWasOn: !current.running.isEmpty, rebuild: true, posts: false,
                prefix: [.destroyAll])
        }
        return settle(
            snapshot, running: current.running, probing: current.probing, proven: [], skip: nil, next: nil,
            fresh: isFresh(state), watchdogWasOn: !current.running.isEmpty, rebuild: false, posts: posts, prefix: [])
    }

    /// Brings the taps in line with a snapshot: destroy what no longer belongs, post new values, rebuild what was
    /// proven, then start at most one probe. `proven` apps build without a probe; every other new app is probed first.
    private static func settle(
        _ snapshot: Snapshot,
        running: [App],
        probing: Probe?,
        proven: [App],
        skip: App?,
        next: Probe?,
        fresh: Bool,
        watchdogWasOn: Bool,
        rebuild: Bool,
        posts: Bool,
        prefix: [Effect]
    ) -> (State, [Effect]) {
        var effects = prefix
        func target(_ app: App) -> Target? { snapshot.targets.first { $0.app.bundleID == app.bundleID } }

        var kept: [App] = []
        for app in running {
            if target(app) != nil { kept.append(app) } else { effects.append(.destroyTap(app)) }
        }
        var probe = probing
        if let current = probing, !(target(current.app)?.isPlaying ?? false) {
            effects.append(.destroyTap(current.app))
            probe = nil
        }

        if posts {
            for app in kept {
                if let found = target(app) { effects.append(.post(app, found.parameters)) }
            }
        }

        var built: [App] = []
        for candidate in snapshot.targets where proven.contains(candidate.app) && !kept.contains(candidate.app) {
            effects.append(.buildTap(candidate.app))
            built.append(candidate.app)
        }
        let before = rebuild ? [] : kept
        kept += built

        if before.isEmpty, !built.isEmpty {
            effects.append(.startWatchdog)
        } else if watchdogWasOn, kept.isEmpty {
            effects.append(.stopWatchdog)
        }

        if probe == nil {
            let forced = next.flatMap { forcedProbe in
                target(forcedProbe.app)?.isPlaying == true && !kept.contains(forcedProbe.app) ? forcedProbe : nil
            }
            if let forced {
                probe = forced
            } else if let first = snapshot.targets.first(where: {
                $0.isPlaying && !kept.contains($0.app) && $0.app != skip
            }) {
                probe = (first.app, 1)
            }
            if let started = probe {
                switch SpectrumGate.decision(permission: snapshot.permission, personAsked: snapshot.personAsked) {
                case .capture:
                    effects.append(.probe(started.app, maxSeconds: EqualiserConsent.probeSeconds(permission: snapshot.permission)))
                case .wait:
                    probe = nil
                case .needsSettings:
                    // A recorded refusal shows the stopped line and waits for "Try again". Nothing is probed or muted.
                    return stop(.silentWhilePlaying(app: started.app.displayName))
                }
            }
        }

        if let probe { return (.probing(probe.app, attempt: probe.attempt, running: kept), effects) }
        if !kept.isEmpty { return (.running(kept), effects) }
        return (fresh ? .waitingForSound : .running([]), effects)
    }

    private static func probeResult(
        _ state: State, app: App, verdict: EqualiserProbeVerdict, seconds: TimeInterval, snapshot: Snapshot
    ) -> (State, [Effect]) {
        guard case .probing(let probing, let attempt, let running) = state, probing == app else { return (state, []) }
        if let pause = snapshot.pause { return (.paused(pause), [.destroyAll, .stopWatchdog]) }
        let fresh = isFresh(state)
        switch verdict {
        case .heard:
            let result = settle(
                snapshot, running: running, probing: nil, proven: [app], skip: nil, next: nil,
                fresh: fresh, watchdogWasOn: !running.isEmpty, rebuild: false, posts: false, prefix: [.recordAllowed])
            return result
        case .silent where seconds >= silentProbeSeconds:
            if EqualiserConsent.stopsAfter(attempt) { return stop(.silentWhilePlaying(app: app.displayName)) }
            return settle(
                snapshot, running: running, probing: nil, proven: [], skip: nil, next: (app, attempt + 1),
                fresh: fresh, watchdogWasOn: !running.isEmpty, rebuild: false, posts: false, prefix: [])
        case .silent, .inconclusive:
            return settle(
                snapshot, running: running, probing: nil, proven: [], skip: app, next: nil,
                fresh: fresh, watchdogWasOn: !running.isEmpty, rebuild: false, posts: false, prefix: [])
        }
    }

    /// Exact zeros under a muted tap while its app plays: destroy that tap first so the app is audible, then probe.
    private static func stall(_ state: State, app: App) -> (State, [Effect]) {
        let current = taps(of: state)
        guard current.running.contains(app) else { return (state, []) }
        let rest = current.running.filter { $0 != app }
        var effects: [Effect] = [.destroyTap(app)]
        if rest.isEmpty { effects.append(.stopWatchdog) }
        if let probing = current.probing {
            // One probe at a time: this app is probed on a later change.
            return (.probing(probing.app, attempt: probing.attempt, running: rest), effects)
        }
        effects.append(.probe(app, maxSeconds: probeSeconds))
        return (.probing(app, attempt: 1, running: rest), effects)
    }

    private static func expire(_ state: State, app: App) -> (State, [Effect]) {
        let current = taps(of: state)
        guard current.running.contains(app) else { return (state, []) }
        let rest = current.running.filter { $0 != app }
        var effects: [Effect] = [.destroyTap(app)]
        if rest.isEmpty { effects.append(.stopWatchdog) }
        if let probing = current.probing {
            return (.probing(probing.app, attempt: probing.attempt, running: rest), effects)
        }
        return (.running(rest), effects)
    }
}

// MARK: - Back-off

/// How long to wait before building a tap again, and how many failures in a row stop that app.
public struct RebuildBackoff: Sendable, Equatable {
    /// Half a second, then one, two and four. The fifth failure inside the window has no delay: it stops.
    public static let delays: [TimeInterval] = [0.5, 1, 2, 4]
    public static let window: TimeInterval = 60

    private var failures: [String: [TimeInterval]] = [:]

    public init() {}

    /// The wait after this many failures inside the window, or nil when it is time to stop. Fewer than one counts as one.
    public static func delay(afterFailures count: Int) -> TimeInterval? {
        let index = max(count, 1) - 1
        return index < delays.count ? delays[index] : nil
    }

    /// Records a failure at `now` seconds and returns how many fall inside the window, this one included.
    public mutating func recordFailure(bundleID: String, at now: TimeInterval) -> Int {
        var times = (failures[bundleID] ?? []).filter { now - $0 < Self.window }
        times.append(now)
        failures[bundleID] = times
        return times.count
    }

    /// Forget one app, after it ran well or was removed.
    public mutating func clear(bundleID: String) {
        failures[bundleID] = nil
    }
}

// MARK: - Watchdog and zeros

public enum EqualiserWatchdog {
    /// No callback for two seconds while the app plays. `elapsed` is the time since `lastBeatCount` was read; a counter
    /// that moved, or went back to a smaller value, is a tap that is alive.
    public static func missed(lastBeatCount: Int64, currentCount: Int64, elapsed: TimeInterval, appPlaying: Bool) -> Bool {
        appPlaying && currentCount == lastBeatCount && elapsed >= 2
    }
}

public enum ZeroWatch {
    public enum Verdict: Sendable, Equatable {
        case fine
        case stalled
    }

    /// Two seconds of exact zeros under a muted tap while the app plays is a stall. A listen-only probe is not muted,
    /// and an app that is not playing is allowed to be silent.
    public static func verdict(zeroFrames: Int64, sampleRate: Double, playing: Bool, muted: Bool) -> Verdict {
        guard playing, muted, sampleRate > 0 else { return .fine }
        return Double(zeroFrames) >= 2 * sampleRate ? .stalled : .fine
    }
}

// MARK: - Status text

public enum EqualiserStatusText {
    /// One line for the card. Every line is words; the symbol only repeats it.
    public static func line(for state: EqualiserLifecycle.State) -> String {
        switch state {
        case .off:
            return "Off. No app is tapped."
        case .waitingForSound:
            return "On. Play something in an app to finish setting up."
        case .probing(let app, _, _):
            return "On. Checking sound from \(app.displayName)."
        case .running(let apps):
            switch apps.count {
            case 0: return "On. Nothing to shape right now."
            case 1: return "Shaping 1 app."
            default: return "Shaping \(apps.count) apps."
            }
        case .paused(let pause):
            switch pause {
            case .callRecording: return "Paused while a call app uses the microphone."
            case .zeusCaptures: return "Paused while Zeus records or captions this Mac's sound."
            case .otherShaper: return "Paused: another copy of Zeus is shaping sound."
            case .asleep: return "Paused while this Mac sleeps."
            case .unsupportedOutput: return "Paused: this output is not supported."
            }
        case .stopped(let stop):
            switch stop {
            case .silentWhilePlaying(let app):
                return "Zeus hears nothing from \(app) while it plays. If System Audio Recording is off for Zeus, turn it on. If you just turned it on, quit and reopen Zeus. Then press Try again."
            case .repeatedFailures(let app):
                return "Stopped shaping \(app) after repeated errors. It plays normally."
            case .startFailed(let status):
                return "Could not start shaping sound (error \(status)). Apps play normally."
            }
        }
    }

    /// An SF Symbol name for the state.
    public static func symbol(for state: EqualiserLifecycle.State) -> String {
        switch state {
        case .off: return "speaker.slash"
        case .waitingForSound: return "speaker.wave.2"
        case .probing: return "ear"
        case .running(let apps): return apps.isEmpty ? "speaker.wave.2" : "waveform"
        case .paused: return "pause.circle"
        case .stopped: return "exclamationmark.triangle"
        }
    }
}
