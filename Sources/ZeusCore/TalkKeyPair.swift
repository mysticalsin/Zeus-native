import Foundation

/// Two talk keys, one talk turn (docs/RIGHT-OPTION-TALK-PLAN.md). A pure arbiter in front of two unchanged
/// `VoiceKeyMachine`s: the primary talk key and the second talk key. STUB: passes the primary through and ignores the second.
public struct TalkKeyPair: Sendable, Equatable {
    public typealias Config = VoiceKeyMachine.Config
    public typealias Event = VoiceKeyMachine.Event
    public typealias Effect = VoiceKeyMachine.Effect

    public enum Slot: Sendable, Equatable, Hashable { case primary, second }

    var primary = VoiceKeyMachine()
    var second = VoiceKeyMachine()
    public internal(set) var owner: Slot?
    public internal(set) var generation = 0
    /// The search turns this off to prove it can see a pair that lets the other key start.
    var arbitrate = true
    /// Effects that belonged to no open turn (P5). The walk asserts it stays 0.
    public internal(set) var strays = 0
    /// The slot the pair bars from starting until every key is up (P4, P8), nil for none.
    var bar: Slot?
    /// What each slot's machine returned in the last call and whether the pair let it through. Read by the search only.
    struct Raw: Equatable { var slot: Slot; var effect: Effect; var emitted: Bool }
    var trace: [Raw] = []

    public init() {}

    public var keys: ShortcutState { primary.keys }
    public var isLatched: Bool { primary.isLatched }

    public mutating func handle(_ event: Event, primary primaryConfig: Config, second secondConfig: Config) -> [Effect] {
        handleTagged(event, primary: primaryConfig, second: secondConfig).map(\.effect)
    }

    mutating func handleTagged(_ event: Event, primary primaryConfig: Config, second secondConfig: Config) -> [(slot: Slot, effect: Effect)] {
        let effects = primary.handle(event, config: primaryConfig)
        generation = primary.generation
        trace = effects.map { Raw(slot: .primary, effect: $0, emitted: true) }
        return effects.map { (Slot.primary, $0) }
    }
}
