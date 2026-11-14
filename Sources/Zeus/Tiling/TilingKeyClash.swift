import AppKit
import Foundation
import ZeusCore

/// Reads the owner's other global keys as the monitors use them and asks the pure rule whether the tiling keys
/// collide with one. The controller refuses to install the tap on a clash, and the Settings page shows the same
/// sentence.
@MainActor
enum TilingKeyClash {
    /// The keys the rule compares, read at one moment. `talk` is the key the owner chose; the rule derives the key
    /// the talk monitor listens on (it moves while VoiceOver runs). Dictation and pointing are nil when off,
    /// exactly as `HotkeyMonitor` reads them.
    struct Keys: Equatable {
        var talk: Shortcut
        var dictation: Shortcut?
        var pointing: Shortcut?
        var chat: ChatHotkey
        var voiceOverOn: Bool

        @MainActor static func live() -> Keys {
            let dictation = DictationSettings.shared
            return Keys(talk: Preferences.shared.pushToTalk,
                        dictation: dictation.enabled ? dictation.key : nil,
                        pointing: PointingSettings.enabled ? PointingSettings.shortcut : nil,
                        chat: ChatHotkey.stored(UserDefaults.standard.string(forKey: "chat.hotkey")),
                        voiceOverOn: NSWorkspace.shared.isVoiceOverEnabled)
        }
    }

    /// The first note for `base`, or nil when the keys are free. Reads settings only; nothing is installed or
    /// prompted. `keys` is the live state unless a caller gives one.
    static func note(base: TileModifierBase, keymap: TileKeymap? = nil, keys: Keys? = nil) -> String? {
        let keys = keys ?? Keys.live()
        return TileBaseConflicts.notes(
            base: base, keymap: keymap ?? TileKeymap.defaults(base: base),
            talk: keys.talk, dictation: keys.dictation, pointing: keys.pointing, chat: keys.chat,
            voiceOverOn: keys.voiceOverOn).first
    }

    /// Calls `changed` on the main actor each time VoiceOver starts or stops, and returns the way to stop watching.
    /// VoiceOver does not write a setting, so the settings observer alone would never see it. The observation
    /// callback can arrive on any thread, so it is installed here, outside the main actor, and hops over.
    nonisolated static func watchVoiceOver(_ changed: @escaping TilingWork) -> () -> Void {
        let observation = NSWorkspace.shared.observe(\.isVoiceOverEnabled) { _, _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { changed() }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { changed() } }
            }
        }
        return { observation.invalidate() }
    }
}
