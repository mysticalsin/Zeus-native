import Foundation

/// The tiling key pair against Zeus's other global keys.
///
/// The tiling tap consumes a bound chord before any other monitor sees it. Talk, pointing and dictation start on
/// the modifiers alone and are cancelled only when a monitor sees another key go down, so a tiling pair that is
/// the same pair as one of those would start a turn on every tiling chord and never cancel it. That pair is
/// refused. A larger pair is clear: those holds need exactly their own modifiers.
public enum TileBaseConflicts {
    /// Plain sentences naming each key that holds `base`, or a chord in `keymap`. Empty when the pair is free.
    public static func notes(base: TileModifierBase, keymap: TileKeymap, talk: Shortcut, dictation: Shortcut?,
                             pointing: Shortcut?, chat: ChatHotkey) -> [String] {
        var out: [String] = []
        var holders: [String] = []
        let holds: [(String, Shortcut?)] = [("Talk to Zeus", talk), ("Pointing", pointing), ("Dictation", dictation)]
        for (name, key) in holds {
            if let key, key.isModifierOnly, key.modifiers == base.modifiers { holders.append(name) }
        }
        if !holders.isEmpty {
            out.append("\(base.label) is also your \(holders.joined(separator: " and ")) key.")
        }
        if let code = chat.keyCode,
           let modifiers = ShortcutConflicts.chatShortcutModifiers(chat),
           keymap.action(for: Shortcut(keyCode: UInt16(code), modifiers: modifiers)) != nil {
            out.append("\(chat.symbols) is both the Chat shortcut and a tiling key.")
        }
        return out
    }
}
