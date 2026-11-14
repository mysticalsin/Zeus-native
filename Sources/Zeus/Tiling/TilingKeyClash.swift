import Foundation
import ZeusCore

/// Reads the owner's other global keys and asks the pure rule whether a tiling key pair collides with one.
/// The controller refuses to install the tap on a clash, and the Settings page shows the same sentence.
@MainActor
enum TilingKeyClash {
    /// The first note for `base`, or nil when the pair is free. Reads settings only; nothing is installed or prompted.
    static func note(base: TileModifierBase, keymap: TileKeymap? = nil) -> String? {
        let dictation = DictationSettings.shared
        return TileBaseConflicts.notes(
            base: base, keymap: keymap ?? TileKeymap.defaults(base: base),
            talk: Preferences.shared.pushToTalk,
            dictation: dictation.enabled ? dictation.key : nil,
            pointing: PointingSettings.enabled ? PointingSettings.shortcut : nil,
            chat: ChatHotkey.stored(UserDefaults.standard.string(forKey: "chat.hotkey"))).first
    }
}
