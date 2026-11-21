import Foundation

/// One physical press starts at most one action.
///
/// A Right Command tap starts Murmur. Holding Right Option talks to Zeus. The two never
/// come from the same press. The clock is the caller's: `at` is the key's own time.
public struct KeyActionRouter: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case murmur
        /// Right Option has been held. Talk starts. This is not a toggle.
        case talk
        /// Right Option was released after talk started. Stop and send. The turn does not stay open.
        case send
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case commandDown(since: TimeInterval, spoiled: Bool)
        case optionDown(since: TimeInterval, spoiled: Bool)
        case talking(since: TimeInterval)
    }

    public enum Event: Equatable, Sendable {
        case rightCommand(down: Bool, at: TimeInterval, otherKeyDown: Bool)
        case leftCommand(down: Bool, at: TimeInterval)
        case rightOption(down: Bool, at: TimeInterval, otherKeyDown: Bool)
        case otherKey(at: TimeInterval)
        case tick(at: TimeInterval)
        case hardwareRightCommandUp(at: TimeInterval)
        case cancel
    }

    /// A Right Command press that lasts longer than this is not a tap.
    public static let commandTapMax: TimeInterval = 0.30
    /// Right Option must be held at least this long before talk starts. A shorter tap does nothing.
    public static let optionHold: TimeInterval = VoiceKey.secondKeyConfirm
    /// Right Option. A release of this key is not held back for a hardware read.
    public static let rightOptionKeyCode: UInt16 = 61

    public private(set) var phase: Phase = .idle
    private var leftCommandDown = false

    public init() {}

    public mutating func send(_ event: Event) -> [Action] {
        switch event {
        case .rightCommand(let down, let at, let other):
            return rightCommand(down: down, at: at, otherKeyDown: other)
        case .leftCommand(let down, let at):
            return leftCommand(down: down, at: at)
        case .rightOption(let down, let at, let other):
            return rightOption(down: down, at: at, otherKeyDown: other)
        case .otherKey(let at):
            return otherKey(at: at)
        case .tick(let at):
            return tick(at: at)
        case .hardwareRightCommandUp:
            return hardwareRightCommandUp()
        case .cancel:
            return cancel()
        }
    }

    private mutating func rightCommand(down: Bool, at: TimeInterval, otherKeyDown: Bool) -> [Action] {
        switch phase {
        case .idle:
            guard down else { return [] }
            phase = .commandDown(since: at, spoiled: otherKeyDown || leftCommandDown)
            return []
        case .commandDown(let since, let spoiled):
            if down { return [] }
            phase = .idle
            let clean = !spoiled && !otherKeyDown && !leftCommandDown
            guard clean, at >= since, at - since <= Self.commandTapMax else { return [] }
            return [.murmur]
        case .optionDown, .talking:
            return []
        }
    }

    private mutating func leftCommand(down: Bool, at: TimeInterval) -> [Action] {
        leftCommandDown = down
        guard down else { return [] }
        return otherKey(at: at)
    }

    /// Hold Right Option to talk. Release stops and sends. Another key does not cancel the hold,
    /// and a repeated down does not toggle it off. There is no latch after the key comes up.
    private mutating func rightOption(down: Bool, at: TimeInterval, otherKeyDown: Bool) -> [Action] {
        _ = otherKeyDown
        switch phase {
        case .idle:
            guard down else { return [] }
            phase = .optionDown(since: at, spoiled: false)
            return []
        case .optionDown:
            if down { return [] }
            phase = .idle
            return []
        case .talking:
            if down { return [] }
            phase = .idle
            return [.send]
        case .commandDown(let since, _):
            if down { phase = .commandDown(since: since, spoiled: true) }
            return []
        }
    }

    private mutating func otherKey(at: TimeInterval) -> [Action] {
        _ = at
        switch phase {
        case .commandDown(let since, _):
            phase = .commandDown(since: since, spoiled: true)
            return []
        case .idle, .optionDown, .talking:
            return []
        }
    }

    private mutating func tick(at: TimeInterval) -> [Action] {
        switch phase {
        case .optionDown(let since, _):
            guard at >= since, at - since >= Self.optionHold else { return [] }
            phase = .talking(since: since)
            return [.talk]
        case .idle, .commandDown, .talking:
            return []
        }
    }

    /// The key-up never arrived. Drop the press and do not start Murmur or talk.
    private mutating func hardwareRightCommandUp() -> [Action] {
        switch phase {
        case .commandDown:
            phase = .idle
            return []
        case .idle, .optionDown, .talking:
            return []
        }
    }

    /// Clears a half-finished Right Command tap. A Right Option hold is push-to-talk and is not cancelled here.
    private mutating func cancel() -> [Action] {
        switch phase {
        case .commandDown:
            phase = .idle
            return []
        case .idle, .optionDown, .talking:
            return []
        }
    }

    /// The owner refused the start. The key may still be down; release then sends nothing.
    public mutating func refuseStart() {
        if case .talking = phase { phase = .idle }
    }
}
