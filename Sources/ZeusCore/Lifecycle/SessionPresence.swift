import Foundation

/// What one read of the login session returned.
public struct SessionFacts: Equatable, Sendable {
    public var screenLocked: Bool
    public var onConsole: Bool

    public init(screenLocked: Bool, onConsole: Bool) {
        self.screenLocked = screenLocked
        self.onConsole = onConsole
    }
}

/// The last read. `unknown` is an unreadable session, which is neither showable nor present.
public enum SessionReading: Equatable, Sendable {
    case locked
    case unlocked
    case unknown
}

/// The last lock or unlock notice. A notice is not a read.
public enum LockHint: Equatable, Sendable {
    case none
    case locked
    case unlocked
}

/// Whether this login session is locked, on the console, awake, and showing a display.
///
/// A notification never sets the reading. It records its own field and asks for a fresh read of the
/// session dictionary. A forged or late notice therefore cannot show the lock card on an unlocked
/// desktop, and a display wake cannot clear a locked reading. Each `readSession` replaces the previous
/// one. The replacement lives with the caller. This file does not read the session and does not start
/// or stop the wake word.
public struct SessionPresence: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case lockNotified
        case unlockNotified
        case sessionBecameActive
        case sessionResigned
        case displaysSlept
        case displaysWoke
        case screensaverStarted
        case screensaverStopped
        case willSleep
        case didWake
        case refreshRequested
        case sessionRead(SessionFacts?)
    }

    public enum Effect: Equatable, Sendable {
        case readSession(after: TimeInterval)
    }

    /// Delays for a notice that said locked while the dictionary still does not. Step zero may replace them.
    public static let settleDelays: [TimeInterval] = [0.5, 1, 2]
    /// Seconds between reads while the dictionary says locked, a display is lit, and the system is awake.
    public static let watchSeconds: TimeInterval = 1

    public private(set) var reading: SessionReading
    public private(set) var hint: LockHint
    public private(set) var onConsole: Bool
    public private(set) var displaysAwake: Bool
    public private(set) var screensaver: Bool
    public private(set) var systemAsleep: Bool
    /// How many settle reads are still allowed. A notice refills it. A read spends one only on the settle path.
    public private(set) var settleLeft: Int

    /// Nothing is showable and nobody is present until the first read. `displaysAwake` is the only seed.
    public init(displaysAwake: Bool) {
        reading = .unknown
        hint = .none
        onConsole = false
        self.displaysAwake = displaysAwake
        screensaver = false
        systemAsleep = false
        settleLeft = 0
    }

    /// Locked, on the console, a display lit, no screensaver, and the system awake.
    public var lockSurfaceMayShow: Bool {
        reading == .locked && onConsole && displaysAwake && !screensaver && !systemAsleep
    }

    /// Both the dictionary and the notices agree the owner is here. Either one saying locked pauses a microphone feature.
    public var ownerPresent: Bool {
        reading == .unlocked && hint != .locked && onConsole && !systemAsleep
    }

    @discardableResult
    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case .lockNotified:
            hint = .locked
            return askForRead()
        case .unlockNotified:
            hint = .unlocked
            return askForRead()
        case .sessionBecameActive:
            onConsole = true
            if hint == .locked { hint = .none }
            return askForRead()
        case .sessionResigned:
            onConsole = false
            return askForRead()
        case .displaysSlept:
            displaysAwake = false
            return askForRead()
        case .displaysWoke:
            displaysAwake = true
            return askForRead()
        case .screensaverStarted:
            screensaver = true
            return askForRead()
        case .screensaverStopped:
            screensaver = false
            return askForRead()
        case .willSleep:
            systemAsleep = true
            return askForRead()
        case .didWake:
            systemAsleep = false
            return askForRead()
        case .refreshRequested:
            return askForRead()
        case .sessionRead(let facts):
            return apply(facts)
        }
    }

    private mutating func askForRead() -> [Effect] {
        settleLeft = Self.settleDelays.count
        return [.readSession(after: 0)]
    }

    private mutating func apply(_ facts: SessionFacts?) -> [Effect] {
        let previous = reading
        if let facts {
            reading = facts.screenLocked ? .locked : .unlocked
            onConsole = facts.onConsole
            if !facts.screenLocked {
                screensaver = false
                if previous == .locked { hint = .none }
            }
        } else {
            reading = .unknown
            onConsole = false
        }

        if reading == .locked, displaysAwake, !systemAsleep {
            return [.readSession(after: Self.watchSeconds)]
        }
        if hint == .locked, reading != .locked, settleLeft > 0 {
            let index = Self.settleDelays.count - settleLeft
            guard Self.settleDelays.indices.contains(index) else { return [] }
            let delay = Self.settleDelays[index]
            settleLeft -= 1
            return [.readSession(after: delay)]
        }
        return []
    }
}
