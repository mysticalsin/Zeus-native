import Foundation

/// The tiling keys against Zeus's other global keys and against VoiceOver.
///
/// The tiling tap consumes a bound chord before any other monitor sees it. Two kinds of clash follow.
///
/// A modifier-only key (talk, pointing, dictation, Polyglot) starts a turn on its modifiers alone and is cancelled only when
/// a monitor sees another key go down. A tiling pair that is the same pair would start a turn on every tiling
/// chord and never cancel it, so that pair is refused.
///
/// A larger pair is free for a hold-style key. It begins only on exactly its own modifiers, and when the owner presses
/// the smaller pair first (Control and Option, then Command) the hold can begin before the rest arrives. Every hold-style
/// monitor therefore cancels a hold that another Control, Option or Command key ends by joining (`HotkeyMonitor`,
/// `PointingKeyGesture`), so nothing is sent, and the tap forwards every key it consumes so a smaller hold that forms when
/// the owner lets go of the extra modifier first stays spoiled (`TileKeyDecision.monitorEvent`). The shared talk and
/// dictation hold begins only after its hold delay and the larger chord cancels it first (`HotkeyMonitor.handleShared`).
///
/// A key that acts on the first press has nothing to cancel. A press-to-toggle dictation key and a modifier-only Polyglot
/// key switch on the moment their own modifiers are down, and a toggle cannot be taken back, so a pair that strictly
/// contains one of them is refused too.
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

    /// A keyed Zeus shortcut other than talk, pointing, dictation and chat (Quick to-do, the notch, the prompter), named for the note.
    public struct NamedShortcut: Equatable, Sendable {
        public var name: String
        public var shortcut: Shortcut

        public init(name: String, shortcut: Shortcut) {
            self.name = name
            self.shortcut = shortcut
        }
    }

    /// Plain sentences naming each key that holds `base`, or a chord in `keymap`. Empty when the keys are free.
    /// `talk` is the key the owner chose; `dictation`, `pointing` and `polyglot` are nil when off. The rule works out the key
    /// the talk monitor listens on from `voiceOverOn`. `dictationToggles` is true when the dictation key toggles on a press
    /// (the Press to toggle behaviour) instead of being held. `others` are the remaining keyed global shortcuts. The
    /// VoiceOver sentence comes first.
    public static func notes(base: TileModifierBase, keymap: TileKeymap, talk: Shortcut, dictation: Shortcut?,
                             pointing: Shortcut?, polyglot: Shortcut?, chat: ChatHotkey, voiceOverOn: Bool,
                             dictationToggles: Bool = false, others: [NamedShortcut] = []) -> [String] {
        var out: [String] = []
        if voiceOverOn, keymap.bindings.contains(where: { $0.shortcut.modifiers.isSuperset(of: voiceOverPair) }) {
            out.append("\(base.label) uses Control and Option, the keys VoiceOver holds while it runs, so tiling cannot use it.")
        }

        let heard = VoiceKey.effectiveTalkKey(chosen: talk, dictation: dictation, pointing: pointing, voiceOverOn: voiceOverOn)
        let talkMoved = heard != talk
        let holds: [(String, Shortcut?)] = [("Talk to Zeus", heard), ("Pointing", pointing), ("Dictation", dictation),
                                        ("Polyglot", polyglot)]

        var holders: [String] = []
        var movedTalkHoldsBase = false
        for (name, key) in holds {
            guard let key, key.isModifierOnly, key.modifiers == base.modifiers else { continue }
            if talkMoved, name == "Talk to Zeus" { movedTalkHoldsBase = true } else { holders.append(name) }
        }
        if !holders.isEmpty {
            out.append("\(base.label) is also your \(holders.joined(separator: " and ")) key.")
        }
        if movedTalkHoldsBase {
            out.append("\(base.label) is also where Talk to Zeus moves while VoiceOver is on.")
        }

        var togglers: [String] = []
        let toggles: [(String, Shortcut?)] = [("Dictation", dictationToggles ? dictation : nil), ("Polyglot", polyglot)]
        for (name, key) in toggles {
            guard let key, key.isModifierOnly, key.modifiers != base.modifiers,
                  key.modifiers.isSubset(of: base.modifiers) else { continue }
            togglers.append(name)
        }
        if !togglers.isEmpty {
            out.append("\(base.label) also holds your \(togglers.joined(separator: " and ")) key, which switches on the moment it is pressed, so tiling cannot use it.")
        }

        for (name, key) in holds {
            guard let key, !key.isModifierOnly, keymap.action(for: key) != nil else { continue }
            out.append("\(key.symbol) is both your \(name) key and a tiling key.")
        }

        if let code = chat.keyCode,
           let modifiers = ShortcutConflicts.chatShortcutModifiers(chat),
           keymap.action(for: Shortcut(keyCode: UInt16(code), modifiers: modifiers)) != nil {
            out.append("\(chat.symbols) is both the Chat shortcut and a tiling key.")
        }
        for other in others where keymap.action(for: other.shortcut) != nil {
            out.append("\(other.shortcut.symbol) is both the \(other.name) shortcut and a tiling key.")
        }
        return out
    }
}
