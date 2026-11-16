import Foundation

/// The tiling keys against Zeus's other global keys and against VoiceOver.
///
/// The tiling tap consumes a bound chord before any other monitor sees it. Two kinds of clash follow, and both read the
/// modifier sets the keymap really binds, not one pair: with the shipped table that is the pair and the pair plus Shift,
/// and an edited keymap can bind any set that holds Control, Option or Command. Fn is left out of every set, because the
/// tap matches an arrow, F or navigation key with or without it, so a key that differs from a bound set only by Fn counts
/// as equal, the safe side. A key that is Fn alone is free.
///
/// A modifier-only key (talk, pointing, dictation, Polyglot) starts a turn on its modifiers alone. The voice key machine
/// (`VoiceKeyMachine`) cancels a turn that another key or modifier joins, and nothing starts again until every key is up,
/// so a larger chord never sends or latches a turn. Two cases are still refused:
///
/// - A hold key whose modifiers equal a bound set. Every chord of that set has exactly the key's modifiers down before its
///   key lands, so the turn would start on every such chord. A dictation hold key is refused one Shift short of a bound set
///   too: Shift joining it only marks the turn, so a chord of the key's modifiers plus Shift would reach its own key before
///   anything foreign showed.
/// - A key that switches on at the press (press to toggle dictation, a modifier-only Polyglot key) whose modifiers are
///   inside a bound set, equal or smaller. The smaller set goes down first, the toggle fires, and a toggle cannot be taken
///   back.
///
/// A hold key strictly inside a bound set is free, but it waits `holdConfirm` while the tiling tap is installed: the owner
/// pressing a chord one key at a time would otherwise open a turn, with its sound, interruption and screen capture, only
/// to cancel it. `confirm(for:keymap:)` is that rule as a pure function.
///
/// A keyed key (a talk, pointing, dictation or Polyglot shortcut with a letter, an arrow or Space) is a chord the tap would
/// swallow if the tiling keymap binds the same chord, so every bound tiling chord is compared with every keyed
/// Zeus shortcut, with the fn flag handled the way the tap handles it.
///
/// The talk key is compared as the talk monitor really listens: while VoiceOver runs, a Control-Option talk key
/// moves to a fallback (`VoiceKey.effectiveTalkKey`). VoiceOver also owns Control-Option itself, alone and with
/// Command and a letter, so while it runs every bound chord that holds Control and Option is refused.
///
/// The other global Zeus keys with a key (Quick to-do, the notch, the prompter pause, the approval answers) are compared the same way.
public enum TileBaseConflicts {
    /// The pair VoiceOver holds while it runs.
    public static let voiceOverPair: ShortcutModifiers = [.control, .option]

    /// How long a hold key waits before it acts while the tiling tap is installed.
    public static let holdConfirm: TimeInterval = 0.15

    /// `holdConfirm` for a modifier-only hold key whose modifiers are strictly inside a set `keymap` binds, 0 for every other
    /// key: one that equals a bound set is refused, not delayed, and one that is inside none, a keyed key and Fn alone
    /// start at once.
    public static func confirm(for key: Shortcut, keymap: TileKeymap) -> TimeInterval {
        let own = key.modifiers.subtracting(.function)
        guard key.isModifierOnly, !own.isEmpty else { return 0 }
        let bound = boundSets(of: keymap)
        guard !bound.contains(own), bound.contains(where: { own.isSubset(of: $0) }) else { return 0 }
        return holdConfirm
    }

    /// The modifier sets of the chords `keymap` binds, in binding order, each once and without Fn.
    private static func boundSets(of keymap: TileKeymap) -> [ShortcutModifiers] {
        var sets: [ShortcutModifiers] = []
        for binding in keymap.bindings {
            let set = binding.shortcut.modifiers.subtracting(.function)
            if !sets.contains(set) { sets.append(set) }
        }
        return sets
    }

    /// The words for a modifier set, as the settings pages write a pair: "Control-Option-Command-Shift".
    private static func name(of set: ShortcutModifiers) -> String {
        let words: [(ShortcutModifiers, String)] = [(.control, "Control"), (.option, "Option"), (.command, "Command"), (.shift, "Shift")]
        return words.filter { set.contains($0.0) }.map(\.1).joined(separator: "-")
    }

    /// Where a modifier-only key meets the bound sets: the first set that equals its modifiers (for a dictation hold key,
    /// with or without Shift), and failing that, for a key that switches on at the press, the first set that holds them.
    private static func meeting(of key: Shortcut, bound: [ShortcutModifiers], switchesOn: Bool,
                                shiftJoins: Bool) -> (set: ShortcutModifiers, equal: Bool)? {
        let own = key.modifiers.subtracting(.function)
        guard key.isModifierOnly, !own.isEmpty else { return nil }
        if let set = bound.first(where: { $0 == own || (shiftJoins && $0 == own.union(.shift)) }) { return (set, true) }
        if switchesOn, let set = bound.first(where: { own.isSubset(of: $0) }) { return (set, false) }
        return nil
    }

    /// The names, grouped under the set they met, in the order the sets first appear.
    private static func grouped(_ items: [(name: String, set: ShortcutModifiers)]) -> [(set: ShortcutModifiers, names: [String])] {
        var groups: [(set: ShortcutModifiers, names: [String])] = []
        for item in items {
            if let index = groups.firstIndex(where: { $0.set == item.set }) {
                groups[index].names.append(item.name)
            } else {
                groups.append((item.set, [item.name]))
            }
        }
        return groups
    }

    /// A keyed Zeus shortcut other than talk, pointing, dictation and chat (Quick to-do, the notch, the prompter), named for the note.
    public struct NamedShortcut: Equatable, Sendable {
        public var name: String
        public var shortcut: Shortcut

        public init(name: String, shortcut: Shortcut) {
            self.name = name
            self.shortcut = shortcut
        }
    }

    /// Plain sentences naming each key that meets a chord in `keymap`. Empty when the keys are free. `base` is the pair the
    /// settings page shows; the rule reads the sets `keymap` binds and names them, so a note never names `base` when the
    /// chord it means is another set. `talk` is the key the owner chose; `dictation`, `pointing` and `polyglot` are nil when
    /// off. The rule works out the key the talk monitor listens on from `voiceOverOn`. `dictationToggles` is true when the
    /// dictation key toggles on a press (the Press to toggle behaviour) instead of being held. `others` are the remaining
    /// keyed global shortcuts. `talkChord` is the chord on the talk key while it is active. `secondTalk` is the second talk key
    /// (Right Option) while it is active, a hold key like talk. The VoiceOver sentence comes first.
    public static func notes(base: TileModifierBase, keymap: TileKeymap, talk: Shortcut, dictation: Shortcut?,
                             pointing: Shortcut?, polyglot: Shortcut?, chat: ChatHotkey, voiceOverOn: Bool,
                             dictationToggles: Bool = false, others: [NamedShortcut] = [],
                             talkChord: Shortcut? = nil, secondTalk: Shortcut? = nil) -> [String] {
        var out: [String] = []
        let bound = boundSets(of: keymap)
        if voiceOverOn, let set = bound.first(where: { $0.isSuperset(of: voiceOverPair) }) {
            out.append("\(name(of: set)) uses Control and Option, the keys VoiceOver holds while it runs, so tiling cannot use it.")
        }

        let heard = VoiceKey.effectiveTalkKey(chosen: talk, dictation: dictation, pointing: pointing, voiceOverOn: voiceOverOn)
        let talkMoved = heard != talk
        let keys: [(name: String, key: Shortcut?, switchesOn: Bool, shiftJoins: Bool)] = [
            ("Talk to Zeus", heard, false, false), ("Pointing", pointing, false, false),
            ("Dictation", dictation, dictationToggles, !dictationToggles), ("Polyglot", polyglot, true, false),
            ("Second talk", secondTalk, false, false),
        ]

        var holders: [(name: String, set: ShortcutModifiers)] = []
        var movedTalk: [(name: String, set: ShortcutModifiers)] = []
        var togglers: [(name: String, set: ShortcutModifiers)] = []
        for item in keys {
            guard let key = item.key,
                  let met = meeting(of: key, bound: bound, switchesOn: item.switchesOn, shiftJoins: item.shiftJoins) else { continue }
            if !met.equal {
                togglers.append((item.name, met.set))
            } else if talkMoved, item.name == "Talk to Zeus" {
                movedTalk.append((item.name, met.set))
            } else {
                holders.append((item.name, met.set))
            }
        }
        for group in grouped(holders) {
            out.append("\(name(of: group.set)) is also your \(group.names.joined(separator: " and ")) key.")
        }
        for group in grouped(movedTalk) {
            out.append("\(name(of: group.set)) is also where Talk to Zeus moves while VoiceOver is on.")
        }
        for group in grouped(togglers) {
            out.append("\(name(of: group.set)) also holds your \(group.names.joined(separator: " and ")) key, which switches on the moment it is pressed, so tiling cannot use it.")
        }

        let holds: [(String, Shortcut?)] = keys.map { ($0.name, $0.key) }
        for (name, key) in holds {
            guard let key, !key.isModifierOnly, keymap.action(for: key) != nil else { continue }
            out.append("\(key.symbol) is both your \(name) key and a tiling key.")
        }

        if let code = chat.keyCode,
           let modifiers = ShortcutConflicts.chatShortcutModifiers(chat),
           keymap.action(for: Shortcut(keyCode: UInt16(code), modifiers: modifiers)) != nil {
            out.append("\(chat.symbols) is both the Chat shortcut and a tiling key.")
        }
        if let talkChord, keymap.action(for: talkChord) != nil {
            out.append("Control-Option-Space is both your Talk to Zeus chord and a tiling key.")
        }
        for other in others where keymap.action(for: other.shortcut) != nil {
            out.append("\(other.shortcut.symbol) is both the \(other.name) shortcut and a tiling key.")
        }
        return out
    }
}
