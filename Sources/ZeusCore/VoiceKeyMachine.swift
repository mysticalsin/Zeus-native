import Foundation

/// One explicit state machine for the voice hold keys (talk, dictation, the Polyglot key): docs/VOICE-KEY-MACHINE-PLAN.md.
/// Pure and without a clock, a timer or a callback. The adapter feeds it keys, the wakes it asked for, an `abandon` when
/// the owner ends or refuses a turn (naming it), a `sweep` for ordinary keys that were let go unseen, and an `interrupt`
/// for sleep and wake; it runs the effects that come back.
public struct VoiceKeyMachine: Sendable, Equatable {
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
        /// The owner refused the press or ended the turn itself. `turn` names the turn it ends: the value `generation`
        /// had once that turn's `start` was counted. A turn the machine has already ended or replaced is not touched.
        case abandon(turn: Int)
        /// Sleep or wake.
        case interrupt(live: ShortcutModifiers?)
        /// The ordinary keys the system reports down now, sent before an event while the picture holds any. A key the
        /// picture holds and the system does not is a key-up nobody saw: it is dropped.
        case sweep(live: Set<UInt16>)
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
    /// How many `start` effects the machine has returned. The first is turn 1. An `abandon` names a turn by this number,
    /// so the owner's echo of a turn the machine ended cannot end the turn that the same call went on to open.
    public internal(set) var generation = 0

    public init() {}

    /// A turn is open and hands-free, or the press that will end it is down.
    public var isLatched: Bool {
        if case .armed(_, .ending) = phase { return true }
        return phase == .latched
    }

    // MARK: Timing

    /// How long a first press may last and still be a tap, and how long after a tap the next one still counts as its
    /// second. A hold key keeps the old talk latch's values, the shared key the old gesture's.
    private static func tapMax(_ config: Config) -> TimeInterval { config.mode == .hold ? 0.3 : 0.25 }
    private static func gap(_ config: Config) -> TimeInterval { config.mode == .hold ? 0.4 : 0.35 }
    /// How often a running hold looks at the live modifiers, to find a release no event reported.
    private static let checkEvery: TimeInterval = 0.25
    /// A wake may arrive this much early: the clock that schedules it and the clock that stamps events differ.
    private static let slack: TimeInterval = 0.001

    /// How long a press waits before it acts: the confirm of a hold key, 0.25 s on a shared dictation key, never on
    /// the talk side of a shared key (it waits for its second tap) or a toggle.
    private static func delay(_ config: Config) -> TimeInterval? {
        switch config.mode {
        case .hold: config.confirm
        case .shared: config.role == .dictation ? 0.25 : nil
        case .toggle: nil
        }
    }

    // MARK: Reading the keys

    private enum Reading {
        /// The whole own set is down and nothing foreign.
        case exact
        /// Not the whole own set, and nothing foreign.
        case released
        /// A dictation key with Shift the one foreign thing down.
        case shifted
        case foreign
    }

    private static func reading(_ facts: KeyFacts, role: Role) -> Reading {
        guard facts.foreignModifier || facts.foreignKey else { return facts.ownDown ? .exact : .released }
        if role == .dictation, facts.foreignModifiers == .shift, !facts.otherSideDown, !facts.foreignKey { return .shifted }
        return .foreign
    }

    private var allUp: Bool { keys.flagModifiers.isEmpty && keys.keysDown.isEmpty }

    /// A turn is open: its microphone is on or its text is waiting for the gap, hands-free included.
    private var turnIsOpen: Bool {
        switch phase {
        case .holding, .latched: true
        case .tapped(_, let open): open
        case .armed(_, let press): press == .ending
        case .idle, .spent: false
        }
    }

    private static func differs(_ old: Config, _ new: Config) -> Bool {
        old.key != new.key || old.mode != new.mode || old.voiceOverHoldsKey != new.voiceOverHoldsKey
    }

    // MARK: Handling an event

    /// One event in, the effects out, in the order the adapter runs them. The order of one call is: the event is
    /// applied to the keyboard picture; a changed config ends the turn it leaves and bars the keys that were already
    /// down before the event; `barred` is brought up to date; then the row of the transition table for the phase and
    /// the reading runs.
    public mutating func handle(_ event: Event, config: Config) -> [Effect] {
        var out: [Effect] = []
        defer { generation += out.filter { $0 == .start }.count }
        let changed = self.config.map { Self.differs($0, config) } ?? false
        // A timer that is overdue acts first, on the keyboard as it was, so a late tick cannot change what a key did.
        if case .key(_, let at) = event, !changed, config.key != nil { settle(at: at, config, &out) }
        let wasAllUp = allUp
        switch event {
        case .key(let shortcutEvent, _): keys.apply(shortcutEvent)
        case .interrupt(let live): if let live { keys.resync(to: live) }
        case .sweep(let live): keys.prune(keysDown: live)
        case .tick, .abandon: break
        }
        self.config = config
        if changed {
            if turnIsOpen { out.append(.cancel) }
            phase = .idle
            // Only a key held through the change is barred. A key that comes down with the event that reveals the change
            // is a new press: the adapter hands the config over with an event, so that event is often the press itself.
            if case .key = event { if !wasAllUp { barred = true } } else if !allUp { barred = true }
        }
        guard let key = config.key else { return out }

        let facts = KeyFacts(of: keys, key: key)
        updateBarred(facts)
        switch event {
        case .abandon(let turn):
            if turn == generation, turnIsOpen { phase = .idle; if !allUp { barred = true } }
        case .sweep:
            break
        case .interrupt:
            if turnIsOpen { out.append(.cancel) }
            phase = .idle
            if !allUp { barred = true }
        case .key(_, let at):
            react(at: at, facts, config, &out)
        case .tick(let at, let live):
            tick(at: at, live: live, key: key, config, &out)
        }
        return out
    }

    /// Nothing may begin until everything is up; a key down with something foreign beside it bars the press.
    private mutating func updateBarred(_ facts: KeyFacts) {
        if facts.allUp {
            barred = false
        } else if facts.ownDown, facts.foreignModifier || facts.foreignKey {
            barred = true
        }
    }

    /// The turn ends without being sent, and nothing begins again until every key is up.
    private mutating func cancelTurn(_ out: inout [Effect]) {
        out.append(.cancel)
        phase = .idle
        if !allUp { barred = true }
    }

    /// A timer that came due before the event that is being handled: rows 5 and 17 on the picture before the event.
    private mutating func settle(at t: TimeInterval, _ config: Config, _ out: inout [Effect]) {
        switch phase {
        case .armed(let since, _):
            if let delay = Self.delay(config), t - since >= delay - Self.slack { delayElapsed(at: t, &out) }
        case .tapped(let tapAt, true):
            if t - tapAt >= Self.gap(config) - Self.slack { phase = .idle; out.append(.send) }
        default:
            break
        }
    }

    /// Row 5: the press has been down alone for its delay.
    private mutating func delayElapsed(at t: TimeInterval, _ out: inout [Effect]) {
        guard case .armed(let since, let press) = phase else { return }
        if press == .ending {
            phase = .spent
            out.append(.send)
        } else {
            phase = .holding(since: since, second: press == .second, check: t + Self.checkEvery, shifted: false)
            out += [.start, .wake(after: Self.checkEvery)]
        }
    }

    // MARK: A tick

    /// Rows 5, 14 and 17. A tick that is not due, or that finds another phase, does nothing.
    private mutating func tick(at t: TimeInterval, live: ShortcutModifiers?, key: Shortcut, _ config: Config,
                               _ out: inout [Effect]) {
        switch phase {
        case .armed(let since, _):
            guard let delay = Self.delay(config), t - since >= delay - Self.slack else { return }
        case .holding(_, _, let check, _):
            guard t >= check - Self.slack else { return }
        case .tapped(let tapAt, true):
            if t - tapAt >= Self.gap(config) - Self.slack { phase = .idle; out.append(.send) }
            return
        default:
            return
        }
        // The live modifiers no longer hold the key's: a release was missed. Take the live picture and read the keys again.
        if let live, !live.isSuperset(of: key.modifiers) {
            keys.resync(to: live)
            let facts = KeyFacts(of: keys, key: key)
            updateBarred(facts)
            react(at: t, facts, config, &out)
            return
        }
        if case .holding(let since, let second, _, let shifted) = phase {
            phase = .holding(since: since, second: second, check: t + Self.checkEvery, shifted: shifted)
            out.append(.wake(after: Self.checkEvery))
        } else {
            delayElapsed(at: t, &out)
        }
    }

    // MARK: A key event

    private mutating func react(at t: TimeInterval, _ facts: KeyFacts, _ config: Config, _ out: inout [Effect]) {
        let reading = Self.reading(facts, role: config.role)
        let begin = reading == .exact && !barred
        switch phase {
        case .idle:
            if begin { beginPress(at: t, config, &out) }

        case .armed(let since, let press):
            switch reading {
            case .exact:
                break
            case .released:
                if config.mode == .shared, config.role == .dictation {
                    phase = .idle                                                           // row 7
                } else if press == .ending {
                    phase = .idle                                                           // row 6, the ending press
                    out.append(.send)
                } else if t - since <= Self.tapMax(config) {
                    if press == .second { phase = .latched; out.append(.start) }            // row 6, the second quick tap
                    else { phase = .tapped(at: t, open: false) }                            // row 6, the first
                } else {
                    phase = .idle
                }
            case .shifted, .foreign:
                phase = press == .ending ? .latched : .idle                                 // row 8
            }

        case .holding(let since, let second, let check, let shifted):
            switch reading {
            case .exact:
                break
            case .released:
                if config.mode == .shared || shifted || t - since > Self.tapMax(config) {
                    phase = .idle                                                           // rows 9 and 10: sent at the release
                    out.append(.send)
                } else if second {
                    phase = .latched                                                        // row 9, the second quick tap
                } else {
                    phase = .tapped(at: t, open: true)                                      // row 9, the first
                    out.append(.wake(after: Self.gap(config)))
                }
            case .foreign:
                cancelTurn(&out)                                                            // row 11
            case .shifted:
                if facts.ownDown {
                    phase = .holding(since: since, second: second, check: check, shifted: true)   // row 12
                } else {
                    phase = .idle                                                           // row 13
                    out.append(.send)
                }
            }

        case .tapped(let tapAt, let open):
            if begin {
                if open {                                                                   // row 15
                    phase = .holding(since: t, second: t - tapAt <= Self.gap(config), check: t + Self.checkEvery, shifted: false)
                    out.append(.wake(after: Self.checkEvery))
                } else {                                                                    // row 18
                    phase = .armed(since: t, press: t - tapAt <= Self.gap(config) ? .second : .first)
                    if config.mode == .hold { out.append(.wake(after: config.confirm)) }
                }
            } else if reading == .foreign || reading == .shifted {
                if open { cancelTurn(&out) } else { phase = .idle }                         // rows 16 and 19
            }

        case .latched:
            if begin { endHandsFreeTurn(at: t, config, &out) }                              // rows 20 and 21

        case .spent:
            if reading != .exact { phase = .idle }                                          // row 22
        }
    }

    /// Rows 1 to 4: a press begins.
    private mutating func beginPress(at t: TimeInterval, _ config: Config, _ out: inout [Effect]) {
        if config.voiceOverHoldsKey {
            phase = .spent
            out.append(.refused)
            return
        }
        switch config.mode {
        case .toggle:
            phase = .spent
            out.append(.start)
        case .hold where config.confirm <= 0:
            phase = .holding(since: t, second: false, check: t + Self.checkEvery, shifted: false)
            out += [.start, .wake(after: Self.checkEvery)]
        case .hold:
            phase = .armed(since: t, press: .first)
            out.append(.wake(after: config.confirm))
        case .shared:
            phase = .armed(since: t, press: .first)
            if config.role == .dictation { out.append(.wake(after: 0.25)) }
        }
    }

    /// Rows 20 and 21: the press that ends a hands-free turn.
    private mutating func endHandsFreeTurn(at t: TimeInterval, _ config: Config, _ out: inout [Effect]) {
        switch config.mode {
        case .hold where config.confirm <= 0:
            phase = .spent
            out.append(.send)
        case .hold:
            phase = .armed(since: t, press: .ending)
            out.append(.wake(after: config.confirm))
        case .shared:
            phase = .armed(since: t, press: .first)
            out.append(.send)
        case .toggle:
            break
        }
    }
}
