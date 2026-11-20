import Foundation

public enum LockScreenPlayback: Equatable, Sendable {
    case none
    case playing
    case paused
}

public enum LockScreenSpaceAnswer: Equatable, Sendable {
    case shown
    case symbolMissing
    case callFailed
}

public enum LockScreenHideReason: String, Equatable, Sendable {
    case settingOff = "setting-off"
    case notLocked = "not-locked"
    case symbolMissing = "symbol-missing"
    case callFailed = "call-failed"
    case noPlayback = "no-playback"

    public var log: String { "lock-screen hidden \(rawValue)" }
}

public enum LockScreenEffect: Equatable, Sendable {
    case play(LockScreenCue)
    case open(id: Int, word: String)
    case close(id: Int)
}

public enum LockScreenHit: Equatable, Sendable {
    case session
    case inertCard
}

public struct LockScreenPointer: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct LockScreenCardBox: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public static let standard = LockScreenCardBox(x: 0, y: 0, width: 280, height: 72)

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func contains(_ point: LockScreenPointer) -> Bool {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite, width > 0, height > 0 else { return false }
        guard point.x.isFinite, point.y.isFinite else { return false }
        return point.x >= x && point.x < x + width && point.y >= y && point.y < y + height
    }
}

/// What may be on the lock screen. The only words are ones Zeus writes.
public struct LockScreenSurface: Equatable, Sendable {
    public var visible: Bool
    public var windowID: Int?
    public var word: String?
    public var controlCount: Int
    public var acceptsCommands: Bool
    public var log: String?

    public static func hidden(_ reason: LockScreenHideReason) -> LockScreenSurface {
        LockScreenSurface(visible: false, windowID: nil, word: nil, controlCount: 0, acceptsCommands: false, log: reason.log)
    }

    public static func shown(id: Int, word: String) -> LockScreenSurface {
        LockScreenSurface(visible: true, windowID: id, word: word, controlCount: 0, acceptsCommands: false, log: nil)
    }
}

public struct LockScreenLedger: Equatable, Sendable {
    public private(set) var openID: Int?
    public private(set) var retired: [Int] = []
    private var nextID = 1

    public init() {}

    mutating func issue() -> Int {
        let id = nextID
        nextID += 1
        return id
    }

    mutating func open(_ id: Int) {
        openID = id
    }

    mutating func retire(_ id: Int) {
        if openID == id { openID = nil }
        retired.append(id)
    }
}

/// One lock-screen session. The card is read-only, and a failed private call leaves nothing up.
public struct LockScreenSession: Equatable, Sendable {
    public private(set) var observation: LockObservation
    public private(set) var settings: LockScreenSettings
    public private(set) var surface: LockScreenSurface
    public private(set) var ledger: LockScreenLedger
    public private(set) var lastCue: LockScreenCue?
    public private(set) var commands: [String]
    public private(set) var spaceAttempts: Int

    public init(settings: LockScreenSettings = .off) {
        observation = .unknown
        self.settings = settings
        surface = .hidden(.settingOff)
        ledger = LockScreenLedger()
        lastCue = nil
        commands = []
        spaceAttempts = 0
        if settings.playerCard {
            surface = .hidden(.notLocked)
        }
    }

    @discardableResult
    public mutating func handle(
        _ event: LockObservationEvent,
        playback: LockScreenPlayback,
        space: (Int) -> LockScreenSpaceAnswer,
        soundFileExists: (String) -> Bool
    ) -> [LockScreenEffect] {
        let previous = observation
        observation = LockObservationMachine.step(observation, event)
        var effects: [LockScreenEffect] = []
        if let cue = LockScreenSounds.cue(settings: settings, from: previous, to: observation, fileExists: soundFileExists) {
            lastCue = cue
            effects.append(.play(cue))
        } else {
            lastCue = nil
        }
        effects += present(playback: playback, space: space)
        return effects
    }

    @discardableResult
    public mutating func replaceSettings(
        _ settings: LockScreenSettings,
        playback: LockScreenPlayback,
        space: (Int) -> LockScreenSpaceAnswer,
        soundFileExists: (String) -> Bool
    ) -> [LockScreenEffect] {
        self.settings = settings
        _ = soundFileExists
        return present(playback: playback, space: space)
    }

    /// A press on the card never runs a command. The name is ignored on purpose.
    public func press(_ name: String) -> Bool {
        _ = name
        return false
    }

    public func hit(_ point: LockScreenPointer, box: LockScreenCardBox = .standard) -> LockScreenHit {
        guard surface.visible, box.contains(point) else { return .session }
        return .inertCard
    }

    private mutating func present(
        playback: LockScreenPlayback,
        space: (Int) -> LockScreenSpaceAnswer
    ) -> [LockScreenEffect] {
        guard settings.playerCard else { return conceal(.settingOff) }
        guard observation == .locked else { return conceal(.notLocked) }
        guard let word = word(for: playback) else { return conceal(.noPlayback) }
        if surface.visible, let id = ledger.openID {
            surface = .shown(id: id, word: word)
            return []
        }
        let id = ledger.issue()
        spaceAttempts += 1
        switch space(id) {
        case .shown:
            ledger.open(id)
            surface = .shown(id: id, word: word)
            return [.open(id: id, word: word)]
        case .symbolMissing:
            ledger.retire(id)
            surface = .hidden(.symbolMissing)
            return []
        case .callFailed:
            ledger.retire(id)
            surface = .hidden(.callFailed)
            return []
        }
    }

    private mutating func conceal(_ reason: LockScreenHideReason) -> [LockScreenEffect] {
        var effects: [LockScreenEffect] = []
        if let id = ledger.openID {
            ledger.retire(id)
            effects.append(.close(id: id))
        }
        surface = .hidden(reason)
        return effects
    }

    private func word(for playback: LockScreenPlayback) -> String? {
        switch playback {
        case .none: return nil
        case .playing: return "Playing"
        case .paused: return "Paused"
        }
    }
}
