import Foundation

/// Two talk keys, one talk turn (docs/RIGHT-OPTION-TALK-PLAN.md): the primary talk key (Control-Option) and a second one
/// (Right Option). A pure arbiter in front of two unchanged `VoiceKeyMachine`s, one owner and one bar. Every event except
/// an `abandon` goes to both machines, primary first, each with its own config; each effect is then let through or not
/// (the rules P1 to P9 of the plan, rules I10 and I11 of docs/VOICE-KEY.md).
///
/// With the second key off the pair is the machine: it passes every effect through, and `aPairWithoutASecondKeyActsAsTheMachine`
/// walks that. Dictation and Polyglot always have the second key off.
public struct TalkKeyPair: Sendable, Equatable {
    public typealias Config = VoiceKeyMachine.Config
    public typealias Event = VoiceKeyMachine.Event
    public typealias Effect = VoiceKeyMachine.Effect

    public enum Slot: Sendable, Equatable, Hashable {
        case primary, second
        var other: Slot { self == .primary ? .second : .primary }
    }

    var primary = VoiceKeyMachine()
    var second = VoiceKeyMachine()
    /// The key whose turn is open. A turn is open from its `start` to its `send`, `cancel` or `abandon`.
    public internal(set) var owner: Slot?
    /// The number the owner's own machine gave that turn: an `abandon` of the pair's turn is forwarded under it.
    var ownerTurn = 0
    /// How many `start` effects the pair has let through. The first is turn 1. An `abandon` names a turn by this number.
    public internal(set) var generation = 0
    /// The slot the pair bars from starting until every key is up: the other key, after a turn ended with a key still down (I11).
    var bar: Slot?
    /// The search turns this off to prove it can see a pair that lets the other key's start through.
    var arbitrate = true
    /// The timers that fell due before a key are delivered ahead of it, across both machines. The search turns this off to prove it
    /// can see a pair that does not.
    var deliverInOrder = true
    /// Effects that belonged to no open turn (P5). The walk asserts it stays 0.
    public internal(set) var strays = 0
    /// What each slot's machine returned in the last call and whether the pair let it through. Read by the search only.
    struct Raw: Equatable {
        var slot: Slot
        var effect: Effect
        var emitted: Bool
        /// Why a start was swallowed: the other key's turn was open (P2), or the bar (P3).
        var cause: Cause?
        /// The effect came from a timer the pair ran ahead of a key (the key had not happened yet when it did).
        var timed = false
        enum Cause: Equatable { case owner, bar }
    }
    var trace: [Raw] = []

    /// The key code a mouse button stands for inside the second key's machine: a foreign key that is down and up at once.
    public static let mouseCode: UInt16 = 0xFFF0

    /// A wake a machine asked for, as the time it falls due: the adapter keeps the real timers, the pair keeps their times so that it
    /// can run what is due ahead of a key, in order, across both machines.
    struct Wake: Equatable { var slot: Slot; var at: TimeInterval }
    var wakes: [Wake] = []
    /// A timer is being run ahead of a key (`deliverDue`).
    private var ahead = false
    /// The time of the last event that carried one: the time a wake asked for in an event with none is counted from.
    var clock: TimeInterval = 0
    private static let slack: TimeInterval = 0.001

    public init() {}

    /// The picture of the keyboard. Both machines hear every key event, so their pictures are the same.
    public var keys: ShortcutState { primary.keys }
    /// The open turn is hands-free (the press that will end it included).
    public var isLatched: Bool { owner.map { machine($0).isLatched } ?? false }

    private func machine(_ slot: Slot) -> VoiceKeyMachine { slot == .primary ? primary : second }

    private var allUp: Bool { keys.flagModifiers.isEmpty && keys.keysDown.isEmpty }

    /// One event in, the effects out. `primary` and `second` are the configs of the two keys now; the second key's is `key: nil`
    /// when it is off.
    public mutating func handle(_ event: Event, primary primaryConfig: Config, second secondConfig: Config) -> [Effect] {
        handleTagged(event, primary: primaryConfig, second: secondConfig).map(\.effect)
    }

    /// A mouse button went down (the owner's decision, docs/RIGHT-OPTION-TALK-PLAN.md): an Option-click or Option-drag is not a talk
    /// turn. It is a foreign key for the second key only, down and up at once: its press is dropped while armed and its turn is
    /// cancelled while held, never sent, and nothing starts until every key is up. The primary key never hears it, and a hands-free
    /// second turn (no key held) stays as it is.
    public mutating func mouseDown(at time: TimeInterval, primary primaryConfig: Config, second secondConfig: Config) -> [Effect] {
        mouseDownTagged(at: time, primary: primaryConfig, second: secondConfig).map(\.effect)
    }

    public mutating func mouseDownTagged(at time: TimeInterval, primary primaryConfig: Config,
                                         second secondConfig: Config) -> [(slot: Slot, effect: Effect)] {
        trace = []
        var out: [(slot: Slot, effect: Effect)] = []
        guard secondConfig.key != nil else { return out }
        deliverDue(upTo: time, live: nil, primaryConfig, secondConfig, &out)
        let flags = second.keys.flagModifiers
        process(.key(.keyDown(keyCode: Self.mouseCode, modifiers: flags), at: time), only: .second, primaryConfig, secondConfig, &out)
        process(.key(.keyUp(keyCode: Self.mouseCode), at: time), only: .second, primaryConfig, secondConfig, &out)
        if allUp { bar = nil }
        return out
    }

    /// `handle`, with the key each effect came from.
    public mutating func handleTagged(_ event: Event, primary primaryConfig: Config,
                                      second secondConfig: Config) -> [(slot: Slot, effect: Effect)] {
        trace = []
        if case .abandon(let turn) = event {
            // P8: the owner's turn ends, in its own machine under its own number. An old turn's echo is ignored.
            if let owner, turn == generation {
                _ = run(owner, .abandon(turn: ownerTurn), primaryConfig, secondConfig)
                end(of: owner)
            }
            return []
        }
        var out: [(slot: Slot, effect: Effect)] = []
        if case .interrupt = event { wakes.removeAll() }
        // Timers that fell due before a key run ahead of it, in due order across both machines. Each machine settles its own overdue
        // timer inside its own call, after the machine before it has been ruled on, so a late timer of the second key would act after
        // the pair had ruled on a key that came later in real time (review of the pair, major 1). The live modifiers are what
        // `settle` reads: those a key-down reports.
        if case .key(let shortcut, let at) = event {
            var live: ShortcutModifiers?
            if case .keyDown(_, let modifiers) = shortcut { live = modifiers.subtracting(.function).union(keys.flagModifiers) }
            deliverDue(upTo: at, live: live, primaryConfig, secondConfig, &out)
        }
        process(event, only: nil, primaryConfig, secondConfig, &out)
        // P9
        if allUp { bar = nil }
        return out
    }

    /// Runs the wakes that are due by `time`, earliest first, as the ticks the adapter would have delivered. Only with a second key
    /// on: with it off the pair is the machine, byte for byte.
    private mutating func deliverDue(upTo time: TimeInterval, live: ShortcutModifiers?, _ primaryConfig: Config, _ secondConfig: Config,
                                     _ out: inout [(slot: Slot, effect: Effect)]) {
        guard deliverInOrder, secondConfig.key != nil else { return }
        while let index = wakes.indices.filter({ wakes[$0].at <= time + Self.slack }).min(by: { wakes[$0].at < wakes[$1].at }) {
            let wake = wakes.remove(at: index)
            ahead = true
            process(.tick(at: wake.at, live: live), only: nil, primaryConfig, secondConfig, &out)
            ahead = false
        }
    }

    /// One event to the machines (`only` names one), each effect let through or not.
    private mutating func process(_ event: Event, only: Slot?, _ primaryConfig: Config, _ secondConfig: Config,
                                  _ out: inout [(slot: Slot, effect: Effect)]) {
        switch event {
        case .key(_, let at), .tick(let at, _): clock = at
        default: break
        }
        if case .tick(let at, _) = event { wakes.removeAll { $0.at <= at + Self.slack } }
        let track = deliverInOrder && secondConfig.key != nil
        if !track { wakes.removeAll() }
        for slot in [Slot.primary, .second] where only == nil || only == slot {
            let before = machine(slot).generation
            var started = 0
            // A start the pair swallowed in this call: the send or cancel the same call gives it belongs to that turn.
            var swallowed = false
            var swallowedWake = false
            for effect in run(slot, event, primaryConfig, secondConfig) {
                var emit = true
                var cause: Raw.Cause?
                switch effect {
                case .start:
                    started += 1
                    swallowedWake = false
                    if arbitrate, (owner.map { $0 != slot } ?? false) || bar == slot {
                        // P2 and P3: the other key's turn is open, or the pair bars this key. The machine is told its turn is over
                        // (it goes idle, barred until every key is up).
                        emit = false
                        cause = (owner.map { $0 != slot } ?? false) ? .owner : .bar
                        swallowed = true
                        swallowedWake = true
                        _ = run(slot, .abandon(turn: before + started), primaryConfig, secondConfig)
                    } else {
                        // P1.
                        owner = slot
                        ownerTurn = before + started
                        generation += 1
                        swallowed = false
                    }
                case .send, .cancel:
                    swallowedWake = false
                    if !arbitrate {
                        if owner != nil { end(of: owner!) }
                    } else if owner == slot {
                        end(of: slot)                       // P4
                    } else {
                        emit = false                        // P5
                        if !swallowed { strays += 1 }
                    }
                case .refused:
                    emit = !(arbitrate && owner != nil)     // P6 and P6b
                case .wake(let after):
                    emit = !swallowedWake                   // P7, but not the check a swallowed turn asked for
                    if emit, track { wakes.append(Wake(slot: slot, at: clock + after)) }
                }
                trace.append(Raw(slot: slot, effect: effect, emitted: emit, cause: cause, timed: ahead))
                if emit { out.append((slot, effect)) }
            }
        }
    }

    /// The owner's turn is over: nobody owns one, and while any key is down the other key waits (I11).
    private mutating func end(of slot: Slot) {
        owner = nil
        if !allUp { bar = slot.other }
    }

    private mutating func run(_ slot: Slot, _ event: Event, _ primaryConfig: Config, _ secondConfig: Config) -> [Effect] {
        switch slot {
        case .primary: primary.handle(event, config: primaryConfig)
        case .second: second.handle(event, config: secondConfig)
        }
    }
}
