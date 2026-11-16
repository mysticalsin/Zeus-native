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
    /// STUB: the timers that fell due before a key are delivered ahead of it, across both machines.
    var deliverInOrder = true
    /// Effects that belonged to no open turn (P5). The walk asserts it stays 0.
    public internal(set) var strays = 0
    /// What each slot's machine returned in the last call and whether the pair let it through. Read by the search only.
    struct Raw: Equatable { var slot: Slot; var effect: Effect; var emitted: Bool }
    var trace: [Raw] = []

    /// The key code a mouse button stands for inside the second key's machine: a foreign key that is down and up at once.
    public static let mouseCode: UInt16 = 0xFFF0

    public init() {}

    /// A mouse button went down: foreign to the second key only. STUB.
    public mutating func mouseDown(at time: TimeInterval, primary primaryConfig: Config, second secondConfig: Config) -> [Effect] {
        mouseDownTagged(at: time, primary: primaryConfig, second: secondConfig).map(\.effect)
    }

    mutating func mouseDownTagged(at time: TimeInterval, primary primaryConfig: Config,
                                  second secondConfig: Config) -> [(slot: Slot, effect: Effect)] { trace = []; return [] }

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

    /// `handle`, with the key each effect came from.
    mutating func handleTagged(_ event: Event, primary primaryConfig: Config,
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
        for slot in [Slot.primary, .second] {
            let before = machine(slot).generation
            var started = 0
            // A start the pair swallowed in this call: the send or cancel the same call gives it belongs to that turn.
            var swallowed = false
            var swallowedWake = false
            for effect in run(slot, event, primaryConfig, secondConfig) {
                var emit = true
                switch effect {
                case .start:
                    started += 1
                    swallowedWake = false
                    if arbitrate, (owner.map { $0 != slot } ?? false) || bar == slot {
                        // P2 and P3: the other key's turn is open, or the pair bars this key. The machine is told its turn is over
                        // (it goes idle, barred until every key is up).
                        emit = false
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
                case .wake:
                    emit = !swallowedWake                   // P7, but not the check a swallowed turn asked for
                }
                trace.append(Raw(slot: slot, effect: effect, emitted: emit))
                if emit { out.append((slot, effect)) }
            }
        }
        // P9
        if allUp { bar = nil }
        return out
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
