import Foundation

/// One explicit state machine for the voice hold keys (talk, dictation, the Polyglot key): docs/VOICE-KEY-MACHINE-PLAN.md.
/// Pure and without a clock, a timer or a callback. The adapter feeds it keys, the wakes it asked for, an `abandon` when
/// the owner ends or refuses a turn, and an `interrupt` for sleep and wake; it runs the effects that come back.
public struct VoiceKeyMachine: Sendable, Equatable, Hashable {
    public enum Role: Sendable, Equatable, Hashable { case talk, dictation }
    public enum Mode: Sendable, Equatable, Hashable { case hold, shared, toggle }

    public struct Config: Sendable, Equatable, Hashable {
        public var key: Shortcut?
        public var role: Role
        public var mode: Mode
        /// VoiceOver is on and the key is Control-Option: a press is refused, not started.
        public var voiceOverHoldsKey: Bool
        /// How long a hold key must be down alone before it acts. 0 except while a tiling chord holds its modifiers.
        public var confirm: TimeInterval

        public init(key: Shortcut?, role: Role, mode: Mode, voiceOverHoldsKey: Bool = false, confirm: TimeInterval = 0) {
            self.key = key
            self.role = role
            self.mode = mode
            self.voiceOverHoldsKey = voiceOverHoldsKey
            self.confirm = confirm
        }
    }

    public enum Event: Sendable, Equatable {
        /// From a monitor or from the consumed key feed: the machine cannot tell which.
        case key(ShortcutEvent, at: TimeInterval)
        /// A wake the machine asked for, with the modifiers the system reports now (nil when it cannot say).
        case tick(at: TimeInterval, live: ShortcutModifiers?)
        /// The owner refused the press or ended the turn itself.
        case abandon
        /// Sleep or wake.
        case interrupt(live: ShortcutModifiers?)
    }

    public enum Effect: Sendable, Equatable {
        case start, send, cancel, refused
        /// Ask for a `tick` this long from now.
        case wake(after: TimeInterval)
    }

    public enum Press: Sendable, Equatable, Hashable {
        case first, second
        /// This press will end a hands-free turn.
        case ending
    }

    public enum Phase: Sendable, Equatable, Hashable {
        /// Nothing open, no press counted.
        case idle
        /// The key is down alone and has not acted yet.
        case armed(since: TimeInterval, press: Press)
        /// A turn is open and the key is down. `shifted`: Shift joined it (dictation role).
        case holding(since: TimeInterval, second: Bool, check: TimeInterval, shifted: Bool)
        /// The key is up after a quick tap. `open`: its turn waits out the gap.
        case tapped(at: TimeInterval, open: Bool)
        /// Hands-free: a turn is open and the key is up.
        case latched
        /// The key is down and this press has done all it will do.
        case spent
    }

    public internal(set) var config: Config?
    /// The picture of the keyboard.
    public internal(set) var keys = ShortcutState()
    /// Nothing may begin until everything is up.
    public internal(set) var barred = false
    public internal(set) var phase: Phase = .idle

    public init() {}

    /// A turn is open and hands-free, or the press that will end it is down.
    public var isLatched: Bool {
        if case .armed(_, .ending) = phase { return true }
        return phase == .latched
    }

    // Placeholder for the failing-tests commit: today's rule, an edge of `isHeld` drives the old talk latch.
    private var stubDown = false

    public mutating func handle(_ event: Event, config: Config) -> [Effect] {
        self.config = config
        guard let key = config.key else { return [] }
        switch event {
        case .key(let shortcutEvent, let at):
            keys.apply(shortcutEvent)
            let pressed = keys.isHeld(key, exact: true)
            defer { stubDown = pressed }
            if pressed, !stubDown {
                switch phase {
                case .latched:
                    phase = .spent
                    return [.send]
                case .tapped(let up, _):
                    phase = .holding(since: at, second: at - up <= 0.4, check: at + 0.25, shifted: false)
                    return []
                default:
                    phase = .holding(since: at, second: false, check: at + 0.25, shifted: false)
                    return [.start]
                }
            }
            if !pressed, stubDown {
                if case .spent = phase { phase = .idle; return [] }
                if case .holding(let since, let second, _, _) = phase {
                    let quick = at - since <= 0.3
                    if second, quick { phase = .latched; return [] }
                    if quick { phase = .tapped(at: at, open: true); return [.wake(after: 0.4)] }
                }
                phase = .idle
                return [.send]
            }
            return []
        case .tick(let at, _):
            if case .tapped(let up, true) = phase, at - up >= 0.4 - 0.001 {
                phase = .idle
                return [.send]
            }
            return []
        case .abandon, .interrupt:
            return []
        }
    }
}
