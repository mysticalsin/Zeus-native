import Foundation

/// The tiling keys against Zeus's other global keys and against VoiceOver.
///
/// The tiling tap consumes a bound chord before any other monitor sees it. Two kinds of clash follow.
///
/// A modifier-only key (talk, pointing, dictation) starts a turn on its modifiers alone and is cancelled only when
/// a monitor sees another key go down. A tiling pair that is the same pair would start a turn on every tiling
/// chord and never cancel it, so that pair is refused. A larger pair is free: those holds need exactly their own
/// modifiers, and a smaller hold that forms when the owner lets go of the extra modifier first stays spoiled because
/// the tap forwards every key it consumes to the monitors (`TileKeyDecision.monitorEvent`).
///
/// A keyed key (a talk, pointing or dictation shortcut with a letter, an arrow or Space) is a chord the tap would
/// swallow if the tiling keymap binds the same chord, so every bound tiling chord is compared with every keyed
/// Zeus shortcut, with the fn flag handled the way the tap handles it.
///
/// The talk key is compared as the talk monitor really listens: while VoiceOver runs, a Control-Option talk key
/// moves to a fallback (`VoiceKey.effectiveTalkKey`). VoiceOver also owns Control-Option itself, alone and with
/// Command and a letter, so while it runs every bound chord that holds Control and Option is refused.
///
/// The other global Zeus keys with a key (Quick to-do, the notch, the prompter pause) are compared the same way.
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
    /// `talk` is the key the owner chose; `dictation` and `pointing` are nil when off. The rule works out the key
    /// the talk monitor listens on from `voiceOverOn`. `others` are the remaining keyed global shortcuts. The
    /// VoiceOver sentence comes first.
    public static func notes(base: TileModifierBase, keymap: TileKeymap, talk: Shortcut, dictation: Shortcut?,
                             pointing: Shortcut?, chat: ChatHotkey, voiceOverOn: Bool,
                             others: [NamedShortcut] = []) -> [String] {
        var out: [String] = []
        if voiceOverOn, keymap.bindings.contains(where: { $0.shortcut.modifiers.isSuperset(of: voiceOverPair) }) {
            out.append("\(base.label) uses Control and Option, the keys VoiceOver holds while it runs, so tiling cannot use it.")
        }

        let heard = VoiceKey.effectiveTalkKey(chosen: talk, dictation: dictation, pointing: pointing, voiceOverOn: voiceOverOn)
        let talkMoved = heard != talk
        let holds: [(String, Shortcut?)] = [("Talk to Zeus", heard), ("Pointing", pointing), ("Dictation", dictation)]

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
