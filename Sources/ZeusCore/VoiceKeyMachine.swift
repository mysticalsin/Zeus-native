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
        /// The code of an ordinary key that may join the held key without spoiling it (Space on Control-Option). Read only
        /// for the talk role in hold mode. Like `confirm` it is stored, not compared: switching it never ends a turn.
        public var chord: UInt16?

        public init(key: Shortcut?, role: Role, mode: Mode, voiceOverHoldsKey: Bool = false, confirm: TimeInterval = 0,
                    chord: UInt16? = nil) {
            self.key = key
            self.role = role
            self.mode = mode
            self.voiceOverHoldsKey = voiceOverHoldsKey
            self.confirm = confirm
            self.chord = chord
        }
    }

    public enum Event: Sendable, Equatable {
        /// From a monitor or from the consumed key feed: the machine cannot tell which. `at` is the time the key itself
        /// went down or up, not the time it was handled: a busy main thread hears a key late, and a timer that is
        /// overdue acts first only when the key came after it (`settle`).
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
    /// The chord key went down while the held key's own set was not down alone (Control, Space, Option; a Command beside the
    /// pair; Space typed with nothing held), so it is foreign until every key is up, as any other key.
    public internal(set) var chordSpoiled = false
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

    /// The windows the walk's age fold is derived from. These are fixed. A test injects its own copy into the harness.
    enum Timing {
        static let step: TimeInterval = 0.05
        static let checkEvery: TimeInterval = 0.25
        static let holdTapMax: TimeInterval = 0.30
        static let sharedTapMax: TimeInterval = 0.25
        static let holdGap: TimeInterval = 0.40
        static let sharedGap: TimeInterval = 0.35
        static let pointingWatchdog: TimeInterval = PointingKeyGesture.watchdog
        static let sharedDictationDelay: TimeInterval = 0.25
        /// One step past the longest gap, so the cap is past every window.
        static var cap: TimeInterval { holdGap + step }

        static func steps(_ seconds: TimeInterval) -> Int { Int((seconds / step).rounded()) }

        /// Step counts of the windows, including `confirm` and the cap. Sorted, with duplicates removed.
        static func cuts(confirm: TimeInterval) -> [Int] {
            let seconds = [0, confirm, checkEvery, holdTapMax, sharedTapMax, holdGap, sharedGap,
                           pointingWatchdog, sharedDictationDelay, cap]
            return Array(Set(seconds.map { Int(($0 / step).rounded()) })).sorted()
        }
    }

    /// How long a first press may last and still be a tap, and how long after a tap the next one still counts as its
    /// second. A hold key keeps the old talk latch's values, the shared key the old gesture's.
    private static func tapMax(_ config: Config) -> TimeInterval {
        config.mode == .hold ? Timing.holdTapMax : Timing.sharedTapMax
    }
    private static func gap(_ config: Config) -> TimeInterval { config.mode == .hold ? Timing.holdGap : Timing.sharedGap }
    /// How often a running hold looks at the live modifiers, to find a release no event reported.
    private static var checkEvery: TimeInterval { Timing.checkEvery }
    /// A wake may arrive this much early: the clock that schedules it and the clock that stamps events differ.
    private static let slack: TimeInterval = 0.001

    /// How long a press waits before it acts: the confirm of a hold key, 0.25 s on a shared dictation key, the confirm
    /// on the press that ends a hands-free turn on the talk side of a shared key. Otherwise never: that side waits for
    /// its second tap, and a toggle acts at the press.
    private static func delay(_ config: Config, _ press: Press) -> TimeInterval? {
        switch config.mode {
        case .hold: config.confirm
        case .shared where config.role == .dictation: Timing.sharedDictationDelay
        case .shared: press == .ending && config.confirm > 0 ? config.confirm : nil
        case .shared, .toggle: nil
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
        /// The whole own set is down, nothing foreign, and the chord key is down too (reading C).
        case chorded
    }

    private static func reading(_ facts: KeyFacts, role: Role) -> Reading {
        guard facts.foreignModifier || facts.foreignKey else {
            guard facts.ownDown else { return .released }
            return facts.chordDown ? .chorded : .exact
        }
        if role == .dictation, facts.foreignModifiers == .shift, !facts.otherSideDown, !facts.foreignKey { return .shifted }
        return .foreign
    }

    /// The chord key the facts may let through: the talk role in hold mode, until the chord key has spoiled the hold.
    private func chord(_ config: Config) -> UInt16? {
        config.role == .talk && config.mode == .hold && !chordSpoiled ? config.chord : nil
    }

    private var allUp: Bool { keys.flagModifiers.isEmpty && keys.keysDown.isEmpty }

    /// A turn is open: its microphone is on or its text is waiting for the gap, hands-free included. Read by the search.
    var turnIsOpen: Bool {
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
        if case .key(let shortcutEvent, let at) = event, !changed, config.key != nil {
            settle(at: at, joined: Self.joinedModifiers(shortcutEvent), config, &out)
        }
        let wasAllUp = allUp
        switch event {
        case .key(let shortcutEvent, _):
            spoilIfChordKeyIsNotClean(shortcutEvent, config)
            keys.apply(shortcutEvent)
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
        guard let key = config.key else {
            // Nothing is read while the key is off, but the picture is kept and the bar still lifts when every key is up.
            if allUp { barred = false }
            return out
        }

        if allUp { chordSpoiled = false }
        let facts = KeyFacts(of: keys, key: key, chord: chord(config))
        updateBarred(facts, config)
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

    /// Nothing may begin until everything is up; a key down with something foreign beside it bars the press, and so does
    /// the chord key down beside the whole set when no press of this set is open (prelude 3): it came before the set.
    private mutating func updateBarred(_ facts: KeyFacts, _ config: Config) {
        if facts.allUp {
            barred = false
        } else if facts.ownDown, facts.foreignModifier || facts.foreignKey || chordSpoiled {
            // A chord key that spoiled the hold stays a spoiler even after the sweep has found it up: the set came after it.
            barred = true
        } else if Self.reading(facts, role: config.role) == .chorded {
            switch phase {
            case .armed, .holding: break
            default: barred = true
            }
        }
    }

    /// The chord key going down when the own set is not down alone spoils the hold, like any other key. Only a Space that
    /// joins the whole set, with nothing else down, is the chord.
    private mutating func spoilIfChordKeyIsNotClean(_ event: ShortcutEvent, _ config: Config) {
        guard case .keyDown(let code, _) = event, let chord = chord(config), code == chord, let key = config.key else { return }
        let before = KeyFacts(of: keys, key: key, chord: chord)
        if !(before.ownDown && !before.foreignModifier && !before.foreignKey) { chordSpoiled = true }
    }

    /// The turn ends without being sent, and nothing begins again until every key is up.
    private mutating func cancelTurn(_ out: inout [Effect]) {
        out.append(.cancel)
        phase = .idle
        if !allUp { barred = true }
    }

    /// The modifiers a key-down reports: what was down when that key went down, so they stand for flags events that may
    /// still be on their way. Fn is left out, an arrow key carries it by itself.
    private static func joinedModifiers(_ event: ShortcutEvent) -> ShortcutModifiers? {
        if case .keyDown(_, let modifiers) = event { return modifiers.subtracting(.function) }
        return nil
    }

    /// A timer that came due before the event that is being handled: rows 5 and 17 on the picture before the event. It
    /// is due only by the event's own time. A key-down that reports a modifier outside the key's set, before the flags
    /// event of that modifier was heard, is read as that event would be, as a tick reads the live modifiers: the press
    /// is dropped, not started.
    private mutating func settle(at t: TimeInterval, joined: ShortcutModifiers?, _ config: Config, _ out: inout [Effect]) {
        switch phase {
        case .armed(let since, let press):
            guard let delay = Self.delay(config, press), t - since >= delay - Self.slack else { return }
            if let joined, let key = config.key,
               readLive(joined, joinedOnly: true, key: key, at: t, config, &out) { return }
            delayElapsed(at: t, config, &out)
        case .tapped(let tapAt, true):
            if t - tapAt >= Self.gap(config) - Self.slack { phase = .idle; out.append(.send) }
        default:
            break
        }
    }

    /// Row 5: the press has been down alone for its delay.
    private mutating func delayElapsed(at t: TimeInterval, _ config: Config, _ out: inout [Effect]) {
        guard case .armed(let since, let press) = phase else { return }
        if press == .ending {
            // On the shared key the press that ended the turn is also the first tap of the next command turn.
            phase = config.mode == .shared ? .armed(since: since, press: .first) : .spent
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
        case .armed(let since, let press):
            guard let delay = Self.delay(config, press), t - since >= delay - Self.slack else { return }
        case .holding(_, _, let check, _):
            guard t >= check - Self.slack else { return }
        case .tapped(let tapAt, true):
            if t - tapAt >= Self.gap(config) - Self.slack { phase = .idle; out.append(.send) }
            return
        default:
            return
        }
        // The live modifiers say what a flags event still on its way would: a modifier of the key let go (a release no
        // event reported), or a foreign one joined (the wake ran before that event). Take them into the picture and read
        // the keys again, so the order of the wake and the queued event decides nothing.
        if let live, readLive(live, joinedOnly: false, key: key, at: t, config, &out) {
            rearmHold(at: t, &out)
            return
        }
        if case .holding = phase {
            rearmHold(at: t, &out)
        } else {
            delayElapsed(at: t, config, &out)
        }
    }

    /// Takes modifiers that stand for a flags event still on its way into the picture and reads the keys again. True when
    /// that changed the reading, or a modifier of the key was let go, and the row for the new reading ran. `joinedOnly`:
    /// the modifiers come from a key-down, which can say a modifier joined but not that one was let go.
    private mutating func readLive(_ live: ShortcutModifiers, joinedOnly: Bool, key: Shortcut, at t: TimeInterval,
                                   _ config: Config, _ out: inout [Effect]) -> Bool {
        let lost = !joinedOnly && !live.isSuperset(of: key.modifiers)
        var liveKeys = keys
        if lost { liveKeys.resync(to: live) } else { liveKeys.adopt(modifiers: joinedOnly ? live.union(keys.flagModifiers) : live) }
        let facts = KeyFacts(of: liveKeys, key: key, chord: chord(config))
        guard lost || Self.reading(facts, role: config.role)
                != Self.reading(KeyFacts(of: keys, key: key, chord: chord(config)), role: config.role) else {
            return false
        }
        keys = liveKeys
        updateBarred(facts, config)
        react(at: t, facts, config, &out)
        return true
    }

    /// Row 14: a hold that is still running looks again after `checkEvery`.
    private mutating func rearmHold(at t: TimeInterval, _ out: inout [Effect]) {
        guard case .holding(let since, let second, _, let shifted) = phase else { return }
        phase = .holding(since: since, second: second, check: t + Self.checkEvery, shifted: shifted)
        out.append(.wake(after: Self.checkEvery))
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
            case .exact, .chorded:
                break                                                                       // rows 5 and 5c
            case .released:
                if config.mode == .shared, config.role == .dictation {
                    phase = .idle                                                           // row 7
                } else if press == .ending {
                    // Row 6, the ending press. On the shared key a quick one is also the first tap of the next turn.
                    phase = config.mode == .shared && t - since <= Self.tapMax(config) ? .tapped(at: t, open: false) : .idle
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
            case .exact, .chorded:
                break                                                                       // rows 11c and 14
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
            } else if reading == .foreign || reading == .shifted || reading == .chorded {
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
            if config.role == .dictation { out.append(.wake(after: Timing.sharedDictationDelay)) }
        }
    }

    /// Rows 20 and 21: the press that ends a hands-free turn. With a confirm it waits for it on a shared key too.
    private mutating func endHandsFreeTurn(at t: TimeInterval, _ config: Config, _ out: inout [Effect]) {
        switch config.mode {
        case .hold where config.confirm <= 0:
            phase = .spent
            out.append(.send)
        case .hold:
            phase = .armed(since: t, press: .ending)
            out.append(.wake(after: config.confirm))
        case .shared where config.confirm > 0:
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
