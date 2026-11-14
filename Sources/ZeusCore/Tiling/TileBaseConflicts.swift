import Foundation

/// The tiling keys against Zeus's other global keys and against VoiceOver.
///
/// The tiling tap consumes a bound chord before any other monitor sees it. Two kinds of clash follow.
///
/// A modifier-only key (talk, pointing, dictation) starts a turn on its modifiers alone and is cancelled only when
/// a monitor sees another key go down. A tiling pair that is the same pair would start a turn on every tiling
/// chord and never cancel it, so that pair is refused. A larger pair is clear: those holds need exactly their own
/// modifiers.
///
/// A keyed key (a talk, pointing or dictation shortcut with a letter, an arrow or Space) is a chord the tap would
/// swallow if the tiling keymap binds the same chord, so every bound tiling chord is compared with every keyed
/// Zeus shortcut, with the fn flag handled the way the tap handles it.
///
/// The talk key is compared as the talk monitor really listens: while VoiceOver runs, a Control-Option talk key
/// moves to a fallback (`VoiceKey.effectiveTalkKey`). VoiceOver also owns the Control-Option pair itself.
public enum TileBaseConflicts {
    /// The pair VoiceOver holds while it runs.
    public static let voiceOverPair: ShortcutModifiers = [.control, .option]

    /// Plain sentences naming each key that holds `base`, or a chord in `keymap`. Empty when the keys are free.
    /// `talk` is the key the owner chose; `dictation` and `pointing` are nil when off. The rule works out the key
    /// the talk monitor listens on from `voiceOverOn`. The VoiceOver sentence comes first.
    public static func notes(base: TileModifierBase, keymap: TileKeymap, talk: Shortcut, dictation: Shortcut?,
                             pointing: Shortcut?, chat: ChatHotkey, voiceOverOn: Bool) -> [String] {
        var out: [String] = []
        if voiceOverOn, base.modifiers == voiceOverPair {
            out.append("\(base.label) is the VoiceOver key pair and VoiceOver is running, so tiling cannot use it.")
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
        return out
    }
}
