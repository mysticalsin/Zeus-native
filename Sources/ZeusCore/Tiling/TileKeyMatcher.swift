import Foundation

/// One key event as the tap sees it, copied out of the system event into plain values. It carries no
/// character and no text: only the key code, which modifiers are held, and two flags.
public struct TileKeyEvent: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case down, up }

    public var phase: Phase
    public var keyCode: UInt16
    public var modifiers: ShortcutModifiers
    /// The system marked this key-down as autorepeat.
    public var isRepeat: Bool
    /// Zeus posted this event itself (it carries `DriveInputAttribution.eventTag`).
    public var isOwnInput: Bool

    public init(phase: Phase, keyCode: UInt16, modifiers: ShortcutModifiers, isRepeat: Bool = false, isOwnInput: Bool = false) {
        self.phase = phase
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.isOwnInput = isOwnInput
    }
}

/// What the tap may do right now.
public struct TileKeyGate: Equatable, Sendable {
    /// Tiling is on. Off means every event passes through.
    public var enabled: Bool
    /// Tiling is paused. Only the chord that resumes it is still taken, so a pause can be undone from the keyboard.
    public var paused: Bool
    /// A secure input field (a password box) is active. Every event passes through.
    public var secureInput: Bool

    public init(enabled: Bool, paused: Bool = false, secureInput: Bool = false) {
        self.enabled = enabled
        self.paused = paused
        self.secureInput = secureInput
    }
}

public enum TileKeyDecision: Equatable, Sendable {
    /// Hand the event to the app it was meant for, untouched.
    case passThrough
    /// Swallow the event. The action, when there is one, is for the tiling controller; nil means the event
    /// belonged to a press that was already taken (its key-up, or a repeat that does not repeat).
    case consume(TileAction?)
}

extension TileKeyDecision {
    /// The keyboard event the other Zeus monitors would have seen had the tap not consumed `event`: the key-down of
    /// a press that was taken, or the key-up that went with it. Nil when the event passed through, or is a repeat
    /// (the monitors skip repeats). A consumed key is a key to the voice key machine: without it the machine would not
    /// see a chord's key land, and a smaller hold that forms the moment the owner lets go of the extra modifier first
    /// would look like a clean press. The machine already bars that hold, so the feed is a second witness.
    public func monitorEvent(for event: TileKeyEvent) -> ShortcutEvent? {
        guard case .consume = self, !event.isOwnInput else { return nil }
        switch event.phase {
        case .down: return event.isRepeat ? nil : .keyDown(keyCode: event.keyCode, modifiers: event.modifiers)
        case .up: return .keyUp(keyCode: event.keyCode)
        }
    }
}

extension TileAction {
    /// Holding the key keeps firing the action. Only moving focus and nudging a split do: a swap, flip, float,
    /// pause, retile or key list would bounce or flicker if autorepeat kept firing it.
    public var repeatsWhileHeld: Bool {
        switch self {
        case .focus, .nudge: true
        case .swap, .flipSplit, .toggleFloat, .togglePause, .retile, .showKeys, .maximizeToggle: false
        }
    }
}

/// Decides, event by event, what the key tap consumes. Pure: no system call, no clock, no text.
///
/// The tap takes an exact bound chord while tiling is on, the key-up of every key-down it took, and the
/// repeats of a press it took. Anything else passes through untouched. The only memory is the set of key
/// codes of presses already taken, so each one can be paired with its key-up.
public struct TileKeyMatcher: Sendable {
    /// Key codes whose key-down was consumed and whose key-up has not come yet.
    private var consumed: Set<UInt16> = []

    public init() {}

    /// Forgets every consumed press. For a tap that was off or restarted.
    public mutating func reset() { consumed.removeAll() }

    public mutating func decide(_ event: TileKeyEvent, keymap: TileKeymap, gate: TileKeyGate) -> TileKeyDecision {
        // Zeus's own synthetic input is never ours to take, and it leaves nothing behind.
        if event.isOwnInput { return .passThrough }

        switch event.phase {
        case .up:
            // The key-up of a press we took goes with it, whatever the gate says now.
            return consumed.remove(event.keyCode) != nil ? .consume(nil) : .passThrough

        case .down where event.isRepeat:
            // A repeat belongs to a press we took, or it is the app's. A chord is never started by a repeat.
            guard consumed.contains(event.keyCode) else { return .passThrough }
            guard let action = Self.match(event, keymap: keymap, gate: gate), action.repeatsWhileHeld else { return .consume(nil) }
            return .consume(action)

        case .down:
            // A new press settles any stale entry left by a key-up that never came.
            guard let action = Self.match(event, keymap: keymap, gate: gate) else {
                consumed.remove(event.keyCode)
                return .passThrough
            }
            consumed.insert(event.keyCode)
            return .consume(action)
        }
    }

    /// The action for a key-down, or nil when it is not ours to take.
    private static func match(_ event: TileKeyEvent, keymap: TileKeymap, gate: TileKeyGate) -> TileAction? {
        guard gate.enabled, !gate.secureInput else { return nil }
        guard let action = keymap.action(for: Shortcut(keyCode: event.keyCode, modifiers: event.modifiers)) else { return nil }
        if gate.paused, action != .togglePause { return nil }
        return action
    }
}

/// Counts how often the system turned the tap off, so a tap that keeps failing is given up on instead of
/// being re-enabled forever. Pure: the caller supplies the time.
public struct TileTapHealth: Sendable {
    public enum Verdict: Equatable, Sendable {
        /// Turn the tap back on.
        case reenable
        /// It keeps failing: stop re-enabling it and tell the owner.
        case giveUp
    }

    public let maxDisables: Int
    public let window: TimeInterval
    private var times: [TimeInterval] = []
    private var gaveUp = false

    /// `maxDisables` disables inside `within` seconds is a run. A limit below two is raised to two, so one
    /// stray disable is always re-enabled.
    public init(maxDisables: Int = 3, within window: TimeInterval = 10) {
        self.maxDisables = max(2, maxDisables)
        self.window = window
    }

    public mutating func recordDisable(at time: TimeInterval) -> Verdict {
        if gaveUp { return .giveUp }
        times.removeAll { time - $0 > window }
        times.append(time)
        if times.count >= maxDisables {
            gaveUp = true
            return .giveUp
        }
        return .reenable
    }

    public mutating func reset() {
        times.removeAll()
        gaveUp = false
    }
}
