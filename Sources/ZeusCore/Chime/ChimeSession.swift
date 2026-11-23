import Foundation

/// A physical close or open of the Mac. Close is lid close, a power button that sleeps or locks
/// the display, or a session lock. Open is wake, unlock, or lid open.
public enum ChimeEvent: String, CaseIterable, Sendable, Equatable {
    case close
    case open
}

/// One system notice the chime watcher can see. Several notices arrive for a single physical event.
public enum ChimeSignal: String, Sendable, Equatable {
    case willSleep
    case didWake
    case screensDidSleep
    case screensDidWake
    case sessionLocked
    case sessionUnlocked
    case willPowerOff

    public var event: ChimeEvent? {
        switch self {
        case .willSleep, .screensDidSleep, .sessionLocked: .close
        case .didWake, .screensDidWake, .sessionUnlocked: .open
        case .willPowerOff: nil
        }
    }
}

/// What the watcher should do with the audio it already has loaded.
public enum ChimeCommand: Sendable, Equatable {
    /// Start this chime now. The first notice of a cluster is the one that plays.
    case play(ChimeEvent)
    /// A shutdown or restart arrived while a close chime was starting. Stop it.
    case cancel
    case none
}

/// Collapses the cluster of sleep, display, and lock notices into one chime.
///
/// The watcher stays quiet until `arm`, so launching Zeus never plays a chime for the session
/// that is already open. `willPowerOff` latches shutdown: that cluster settles to silence.
public struct ChimeDebouncer: Sendable {
    /// Notices for one lid close or wake arrive together, well inside this window.
    public static let clusterWindow: TimeInterval = 1

    private var armed = false
    private var poweringOff = false
    private var powerOffAt: TimeInterval?
    private var lastPlay: (event: ChimeEvent, at: TimeInterval)?
    private var closeStartedAt: TimeInterval?

    public init() {}

    /// Begin accepting notices. Arming itself plays nothing.
    public mutating func arm() {
        armed = true
    }

    public mutating func receive(_ signal: ChimeSignal, at time: TimeInterval) -> ChimeCommand {
        guard armed else { return .none }
        if signal == .willPowerOff {
            poweringOff = true
            powerOffAt = time
            if let started = closeStartedAt, time >= started, time - started <= Self.clusterWindow {
                closeStartedAt = nil
                lastPlay = nil
                return .cancel
            }
            return .none
        }
        if poweringOff {
            // A wake means the Mac came back. A notice after the cluster means shutdown was cancelled
            // and this process is still here. Either one clears the latch.
            let woke = signal.event == .open
            let cancelled = powerOffAt.map { time >= $0 && time - $0 > Self.clusterWindow } ?? false
            if woke || cancelled {
                poweringOff = false
                powerOffAt = nil
            } else {
                return .none
            }
        }
        guard let event = signal.event else { return .none }
        if let previous = lastPlay, previous.event == event, time >= previous.at, time - previous.at <= Self.clusterWindow {
            return .none
        }
        lastPlay = (event, time)
        closeStartedAt = event == .close ? time : nil
        return .play(event)
    }

    /// The chime that is still sounding after the notices, once a cancel has been applied.
    public static func settled(_ commands: [ChimeCommand]) -> ChimeEvent? {
        var playing: ChimeEvent?
        for command in commands {
            switch command {
            case .play(let event): playing = event
            case .cancel: playing = nil
            case .none: break
            }
        }
        return playing
    }
}

/// Whether a chime may start. Focus is a separate input so this stays free of system frameworks.
public enum ChimePlaybackGate {
    /// Sound feedback off, a meeting, or an unknown Focus state keeps the chime quiet.
    /// Omitting Focus means it is unknown. Focus suppresses only when it is known to be on.
    /// The caller must not ask for Focus permission.
    public static func allows(enabled: Bool, focusActive: Bool, soundFeedback: Bool = true, meeting: Bool = false, focusKnown: Bool = false) -> Bool {
        guard enabled, soundFeedback, !meeting, focusKnown else { return false }
        return !focusActive
    }
}

/// Whether the lock and wake settings card accepts input.
/// Sound feedback off leaves the whole card inactive. Play also follows the chime toggle.
public enum ChimeCardGate {
    public static func interactive(soundFeedback: Bool) -> Bool {
        soundFeedback
    }

    public static func playEnabled(soundFeedback: Bool, chimeEnabled: Bool) -> Bool {
        interactive(soundFeedback: soundFeedback) && chimeEnabled
    }
}
