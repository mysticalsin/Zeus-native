import Foundation

/// What the home and music transport can ask a now-playing source to do.
public enum MediaControlCommand: Equatable, Sendable {
    case play
    case pause
    case next
    case previous
    case seek(Double)
}

/// Where a command is delivered. A scripted player is addressed by bundle id. A browser tab is the
/// tab and document the existing browser feed already holds.
public struct MediaCommandRoute: Equatable, Sendable {
    public enum Endpoint: Equatable, Sendable {
        case scriptedPlayer(bundleID: String)
        case browser(tabID: Int, documentID: String)
    }

    public var endpoint: Endpoint
    /// Previous and next are both available.
    public var canSkip: Bool
    public var canSeek: Bool

    public init(endpoint: Endpoint, canSkip: Bool, canSeek: Bool) {
        self.endpoint = endpoint
        self.canSkip = canSkip
        self.canSeek = canSeek
    }
}

/// One sample of what is actually playing. Nil means no source.
public struct MediaNowPlayingSample: Equatable, Sendable {
    public var isPlaying: Bool
    public var position: Double
    public var duration: Double
    public var route: MediaCommandRoute

    public init(isPlaying: Bool, position: Double, duration: Double, route: MediaCommandRoute) {
        self.isPlaying = isPlaying
        self.position = position
        self.duration = duration
        self.route = route
    }
}

/// The playback state the transport is allowed to be in.
public enum MediaCommandState: Equatable, Sendable {
    case unknown
    case playing
    case paused
    case noSource
    case commandPending(MediaControlCommand)
    case failed(MediaCommandFailure)
}

public enum MediaCommandFailure: Equatable, Sendable {
    /// The system will not let the command through. The recovery action opens Settings.
    case permissionDenied
    /// The command was attempted and the source did not take it.
    case unavailable
}

public enum MediaCommandDelivery: Equatable, Sendable {
    case accepted
    case permissionDenied
    case unavailable
    case failed
}

public enum MediaCommandEvent: Equatable, Sendable {
    case info(MediaNowPlayingSample?)
    case press(MediaControlCommand)
    case result(MediaCommandDelivery)
    case recover
}

public enum MediaCommandEffect: Equatable, Sendable {
    case send(MediaControlCommand, MediaCommandRoute)
    /// Read the real now-playing sample again, `after` seconds from the press. Always under 0.15.
    case resync(MediaCommandRoute, after: Double)
    case openRecovery
}

public struct MediaCommandRejection: Error, Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case illegalTransition
        case duplicate
        case unsupported
        case inFlight
        case blocked
    }

    public var reason: Reason

    public init(_ reason: Reason) { self.reason = reason }
}

/// One router for play, pause, next, previous and seek. Illegal transitions throw and change nothing.
/// A press with no source sends nothing. A second press inside the debounce window sends nothing.
public struct MediaCommandRouter: Equatable, Sendable {
    /// A second press inside this window is a double-tap, not a new command.
    public static let debounceWindow: Double = 0.25
    /// How soon the real sample should replace a pending command. Under the 150 ms budget.
    public static let resyncDelay: Double = 0.12
    /// How often to look again while a permission check is still in flight.
    public static let permissionRecheck: Double = 0.04

    public private(set) var state: MediaCommandState
    public private(set) var route: MediaCommandRoute?
    public private(set) var position: Double
    public private(set) var duration: Double

    private var reportedPlaying = false
    private var pendingSince: Double?
    private var pendingWasPlaying = false
    private var lastCommandAt: Double?
    /// Contradicting samples before this time are the old state, still in flight.
    private var holdContradictionsUntil: Double?

    public init() {
        state = .unknown
        route = nil
        position = 0
        duration = 0
    }

    public mutating func reduce(_ event: MediaCommandEvent, now: Double) throws -> [MediaCommandEffect] {
        switch event {
        case .info(let sample):
            return apply(sample, now: now)
        case .press(let command):
            return try press(command, now: now)
        case .result(let delivery):
            return try finish(delivery, now: now)
        case .recover:
            return try recover()
        }
    }

    // MARK: Samples

    private mutating func apply(_ sample: MediaNowPlayingSample?, now: Double) -> [MediaCommandEffect] {
        guard let sample else {
            state = .noSource
            route = nil
            position = 0
            duration = 0
            reportedPlaying = false
            pendingSince = nil
            holdContradictionsUntil = nil
            return []
        }
        if case .failed(.permissionDenied) = state {
            route = sample.route
            position = sample.position
            duration = sample.duration
            reportedPlaying = sample.isPlaying
            return []
        }
        if let until = holdContradictionsUntil, now < until {
            let expected: Bool
            if case .commandPending(let command) = state {
                expected = Self.expectsPlaying(command, wasPlaying: pendingWasPlaying)
            } else {
                expected = reportedPlaying
            }
            if sample.isPlaying != expected { return [] }
        }
        route = sample.route
        position = sample.position
        duration = sample.duration
        reportedPlaying = sample.isPlaying
        state = sample.isPlaying ? .playing : .paused
        pendingSince = nil
        return []
    }

    // MARK: Presses

    private mutating func press(_ command: MediaControlCommand, now: Double) throws -> [MediaCommandEffect] {
        if case .commandPending = state { throw MediaCommandRejection(.inFlight) }
        if let last = lastCommandAt, now - last < Self.debounceWindow {
            throw MediaCommandRejection(.duplicate)
        }
        switch state {
        case .unknown:
            throw MediaCommandRejection(.illegalTransition)
        case .noSource:
            return []
        case .failed(.permissionDenied):
            throw MediaCommandRejection(.blocked)
        case .failed(.unavailable):
            guard route != nil else { return [] }
            return try begin(command, playing: reportedPlaying, now: now)
        case .playing:
            return try begin(command, playing: true, now: now)
        case .paused:
            return try begin(command, playing: false, now: now)
        case .commandPending:
            throw MediaCommandRejection(.inFlight)
        }
    }

    private mutating func begin(_ command: MediaControlCommand, playing: Bool, now: Double) throws -> [MediaCommandEffect] {
        switch command {
        case .play:
            guard !playing else { throw MediaCommandRejection(.illegalTransition) }
        case .pause:
            guard playing else { throw MediaCommandRejection(.illegalTransition) }
        case .next, .previous:
            guard route?.canSkip == true else { throw MediaCommandRejection(.unsupported) }
        case .seek(let seconds):
            guard route?.canSeek == true, duration > 0, seconds.isFinite else { throw MediaCommandRejection(.unsupported) }
        }
        guard let route else { throw MediaCommandRejection(.illegalTransition) }
        let outgoing = Self.normalize(command, duration: duration)
        state = .commandPending(outgoing)
        pendingSince = now
        pendingWasPlaying = playing
        lastCommandAt = now
        holdContradictionsUntil = now + Self.resyncDelay
        return [.send(outgoing, route), .resync(route, after: Self.resyncDelay)]
    }

    private static func normalize(_ command: MediaControlCommand, duration: Double) -> MediaControlCommand {
        guard case .seek(let seconds) = command else { return command }
        return .seek(MusicSeek.clampedTarget(seconds, duration: duration))
    }

    private static func expectsPlaying(_ command: MediaControlCommand, wasPlaying: Bool) -> Bool {
        switch command {
        case .play: true
        case .pause: false
        case .next, .previous, .seek: wasPlaying
        }
    }

    // MARK: Results

    private mutating func finish(_ delivery: MediaCommandDelivery, now: Double) throws -> [MediaCommandEffect] {
        guard case .commandPending(let command) = state else { throw MediaCommandRejection(.illegalTransition) }
        switch delivery {
        case .accepted:
            switch command {
            case .play:
                reportedPlaying = true
                state = .playing
            case .pause:
                reportedPlaying = false
                state = .paused
            case .next, .previous:
                reportedPlaying = pendingWasPlaying
                state = pendingWasPlaying ? .playing : .paused
            case .seek(let seconds):
                position = seconds
                reportedPlaying = pendingWasPlaying
                state = pendingWasPlaying ? .playing : .paused
            }
            // The read-back lands just after this. A sample that still shows the old state is ignored until then.
            holdContradictionsUntil = now + Self.resyncDelay * 2
        case .permissionDenied:
            state = .failed(.permissionDenied)
        case .unavailable:
            state = .noSource
            route = nil
            position = 0
            duration = 0
            reportedPlaying = false
        case .failed:
            state = .failed(.unavailable)
        }
        pendingSince = nil
        if delivery != .accepted { holdContradictionsUntil = nil }
        return []
    }

    private mutating func recover() throws -> [MediaCommandEffect] {
        guard case .failed(.permissionDenied) = state else { throw MediaCommandRejection(.illegalTransition) }
        if route == nil {
            state = .noSource
            reportedPlaying = false
        } else if reportedPlaying {
            state = .playing
        } else {
            state = .paused
        }
        pendingSince = nil
        return [.openRecovery]
    }
}

// MARK: - What the controls say

public enum MediaControlActivation: Equatable, Sendable {
    case press(MediaControlCommand)
    case recover
}

public struct MediaControlAccessibility: Equatable, Sendable {
    public var playLabel: String
    public var pauseLabel: String
    public var playHint: String
    public var pauseHint: String
    public var previousLabel: String
    public var previousHint: String
    public var nextLabel: String
    public var nextHint: String
    public var seekLabel: String
    public var seekHint: String
    public var recoveryLabel: String
    public var recoveryHint: String
    public var value: String
}

public enum MediaControlPresentation {
    public static let recoveryLabel = "Allow playback control"
    public static let seekLabel = "Playback position"
    public static let seekHint = "Moves the playhead."

    public static func showsRecovery(_ state: MediaCommandState) -> Bool {
        if case .failed(.permissionDenied) = state { return true }
        return false
    }

    public static func showsPause(_ state: MediaCommandState, fallbackPlaying: Bool) -> Bool {
        switch state {
        case .unknown: fallbackPlaying
        case .playing: true
        case .paused, .noSource: false
        case .failed(.permissionDenied): false
        case .failed(.unavailable): fallbackPlaying
        case .commandPending(let command):
            switch command {
            case .play: false
            case .pause: true
            case .next, .previous, .seek: fallbackPlaying
            }
        }
    }

    public static func activation(_ state: MediaCommandState, fallbackPlaying: Bool) -> MediaControlActivation {
        if showsRecovery(state) { return .recover }
        if case .failed(.unavailable) = state { return .press(fallbackPlaying ? .pause : .play) }
        return .press(showsPause(state, fallbackPlaying: fallbackPlaying) ? .pause : .play)
    }

    /// Spoken only when the transport has nothing to control, or the last command failed.
    public static func guidance(for state: MediaCommandState) -> String? {
        switch state {
        case .noSource:
            "Nothing is playing. Start playback, then these controls follow it."
        case .failed(.permissionDenied):
            "Playback controls need permission."
        case .failed(.unavailable):
            "The player did not answer. Try again."
        case .unknown, .playing, .paused, .commandPending:
            nil
        }
    }

    public static func accessibility(for state: MediaCommandState, fallbackPlaying: Bool) -> MediaControlAccessibility {
        MediaControlAccessibility(
            playLabel: "Play",
            pauseLabel: "Pause",
            playHint: "Plays the current track.",
            pauseHint: "Pauses the current track.",
            previousLabel: "Previous track",
            previousHint: "Plays the previous track.",
            nextLabel: "Next track",
            nextHint: "Plays the next track.",
            seekLabel: seekLabel,
            seekHint: seekHint,
            recoveryLabel: recoveryLabel,
            recoveryHint: "Opens Settings to allow playback control.",
            value: spokenValue(state, fallbackPlaying: fallbackPlaying))
    }

    /// Press feedback scale. Reduce Motion holds the control at rest.
    public static func pressScale(reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : MotionTokens.pressScale
    }

    /// The transport buttons do not run their own motion. Reduce Motion also drops the press scale.
    public static func animatesPress(reduceMotion: Bool) -> Bool { !reduceMotion }

    private static func spokenValue(_ state: MediaCommandState, fallbackPlaying: Bool) -> String {
        switch state {
        case .unknown: fallbackPlaying ? "Playing" : "Nothing playing"
        case .playing: "Playing"
        case .paused: "Paused"
        case .noSource: "Nothing playing"
        case .commandPending: "Sending"
        case .failed(.permissionDenied): "Needs permission"
        case .failed(.unavailable): "Not available"
        }
    }
}

/// Private media-remote commands are not on an approved item in this tree. The gate stays off,
/// and every attempt fails closed even if a caller asks.
public enum MediaRemoteCommandGate {
    public static let enabled = false

    public static func attempt(_ command: MediaControlCommand) -> MediaCommandDelivery {
        _ = command
        return .unavailable
    }
}
