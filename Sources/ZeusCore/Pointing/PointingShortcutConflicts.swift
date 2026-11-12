import Foundation

extension Shortcut {
    /// The Fn+Control preset for the existing dictation key (Phase 2). Offered, never forced.
    public static let functionControl = Shortcut(modifiers: [.function, .control])
}

extension ShortcutConflicts {
    /// Warnings for the pointing key against the other global keys. Warnings only; nothing blocks.
    /// `showMeKey` is the show-me hold (left Command by default).
    public static func pointingWarnings(pointing: Shortcut, talk: Shortcut, dictation: Shortcut?, chat: ChatHotkey,
                                        doubleControlTextEntry: Bool,
                                        showMeKey: Shortcut = Shortcut(modifiers: .command, side: .left),
                                        voiceOverOn: Bool = false) -> [String] {
        var out = warnings(for: pointing, other: nil, otherName: "", voiceOverOn: voiceOverOn)
        // The same key as Talk to Zeus is the shipped design, not a conflict: the talk turn owns that hold
        // (`VoiceKey.pointingStartsTurns`), so one hold is one turn.
        if pointing != talk { out += keyed(pointing, against: talk, name: "Talk to Zeus") }
        if let dictation { out += keyed(pointing, against: dictation, name: "Dictation") }
        out += keyed(pointing, against: showMeKey, name: "Show me")
        if chat != .off, let chatModifiers = chatShortcutModifiers(chat), pointing.isModifierOnly,
           chatModifiers.isSuperset(of: pointing.modifiers) {
            out.append("The Chat shortcut starts with these keys. Pressing it cancels the pointing hold and sends nothing.")
        }
        if doubleControlTextEntry {
            if pointing.isModifierOnly, pointing.modifiers == .control {
                out.append("Double-tap Control for text entry overlaps a pointing key that is Control alone.")
            }
            let loneControl = Shortcut(modifiers: .control)
            if talk == loneControl || dictation == loneControl {
                out.append("Double-tap Control for text entry overlaps your talk or dictation key (Control alone).")
            }
            out.append("Double-tap Control may also be macOS Dictation's \"Press Control key twice\" shortcut. Turn one off if both fire.")
        }
        return out
    }

    /// Two modifier-only chords where `other` extends `pointing`: the pointing hold starts first and is
    /// then cancelled by the extra key. It never sends a request, but the marker flashes.
    private static func keyed(_ pointing: Shortcut, against other: Shortcut, name: String) -> [String] {
        guard pointing.isModifierOnly, other.isModifierOnly else { return [] }
        if pointing == other { return ["Same key as \(name). Use a different key for pointing."] }
        if pointing.modifiers == other.modifiers { return overlaps(pointing, other) ? ["Overlaps \(name). Use a different key."] : [] }
        if other.modifiers.isSuperset(of: pointing.modifiers) {
            return ["Holding \(name) (\(other.title)) first holds \(pointing.title), so the pointing marker flashes and cancels."]
        }
        return []
    }

    private static func chatShortcutModifiers(_ chat: ChatHotkey) -> ShortcutModifiers? {
        guard chat != .off else { return nil }
        var mods: ShortcutModifiers = []
        if chat.modifiers.contains(.control) { mods.insert(.control) }
        if chat.modifiers.contains(.option) { mods.insert(.option) }
        if chat.modifiers.contains(.shift) { mods.insert(.shift) }
        if chat.modifiers.contains(.command) { mods.insert(.command) }
        return mods
    }
}

/// The Fn+Control dictation preset: switching it on remembers the old key, switching it off puts it back.
/// Pure: strings are `Shortcut.stored` values, so the app only reads and writes defaults.
public enum DictationFnControlPreset {
    public static let savedKey = "dictation.shortcut.beforeFnControl"

    /// The dictation value to write and the value to remember, or nil when nothing changes.
    public static func next(wanted: Bool, current: String, saved: String?) -> (key: String, saved: String?)? {
        let preset = Shortcut.stored(.functionControl)
        if wanted {
            guard current != preset else { return nil }
            return (preset, current)
        }
        guard current == preset else { return nil }
        return (saved ?? Shortcut.stored(.rightCommand), nil)
    }
}
