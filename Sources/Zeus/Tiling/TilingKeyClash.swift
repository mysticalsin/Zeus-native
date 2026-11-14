import AppKit
import Carbon.HIToolbox
import Foundation
import ZeusCore

extension ShortcutPreset {
    /// The preset as a keyed shortcut, or nil when it is off. Quick to-do and the notch use these as global hot keys.
    var tilingShortcut: Shortcut? {
        guard let code = keyCode else { return nil }
        var modifiers: ShortcutModifiers = []
        let mask = self.modifiers
        if mask & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if mask & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if mask & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if mask & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        return Shortcut(keyCode: UInt16(code), modifiers: modifiers)
    }
}

/// Reads the owner's other global keys as the monitors use them and asks the pure rule whether the tiling keys
/// collide with one. The controller refuses to install the tap on a clash, and the Settings page shows the same
/// sentence.
@MainActor
enum TilingKeyClash {
    /// The keys the rule compares, read at one moment. `talk` is the key the owner chose; the rule derives the key
    /// the talk monitor listens on (it moves while VoiceOver runs). Dictation and pointing are nil when off,
    /// exactly as `HotkeyMonitor` reads them. Polyglot is the same: its monitor is a `HotkeyMonitor` too, and it
    /// hears every key the tap forwards. `TilingKeyClashTests` lists every monitor and every `HotKeyCenter` binding in
    /// the app, so a new global key cannot be left out of this struct unnoticed.
    struct Keys: Equatable {
        var talk: Shortcut
        var dictation: Shortcut?
        var pointing: Shortcut?
        var polyglot: Shortcut?
        var chat: ChatHotkey
        var voiceOverOn: Bool
        /// The other global hot keys with a key: Quick to-do, the notch, the prompter pause and the approval answer keys.
        var others: [TileBaseConflicts.NamedShortcut] = []

        /// The prompter's pause key (`PrompterHub.hotkeys`). It is registered only while the prompter shows, but it is
        /// fixed, so the tiling keys must never bind it.
        static let prompterPause = TileBaseConflicts.NamedShortcut(
            name: "Prompter pause", shortcut: Shortcut(keyCode: UInt16(kVK_ANSI_P), modifiers: [.control, .option]))

        /// The approval answer keys (`AppDelegate.answerKeys`): Control-Option Y, N and O answer a waiting request. They
        /// are registered through `HotKeyCenter` only while a request waits, but they are fixed, so while the setting
        /// is on the tiling keys must never bind them.
        static let approvalAnswers: [TileBaseConflicts.NamedShortcut] = [
            ("Approve request", kVK_ANSI_Y), ("Deny request", kVK_ANSI_N), ("Open request", kVK_ANSI_O),
        ].map { name, code in
            TileBaseConflicts.NamedShortcut(name: name, shortcut: Shortcut(keyCode: UInt16(code), modifiers: [.control, .option]))
        }

        /// `answerKeysOn` is the "Answer permissions from the keyboard" setting.
        @MainActor static func live(answerKeysOn: Bool = SettingsStore.shared.bool("shortcut.answerKeys")) -> Keys {
            let dictation = DictationSettings.shared
            let extras = ExtraPreferences.shared
            let polyglot = PolyglotSettings.shared
            let presets: [(String, ShortcutPreset)] = [("Open the notch", extras.openNotch), ("Quick to-do", extras.quickTodo)]
            return Keys(talk: Preferences.shared.pushToTalk,
                        dictation: dictation.enabled ? dictation.key : nil,
                        pointing: PointingSettings.enabled ? PointingSettings.shortcut : nil,
                        polyglot: polyglot.enabled ? polyglot.hotkey : nil,
                        chat: ChatHotkey.stored(UserDefaults.standard.string(forKey: "chat.hotkey")),
                        voiceOverOn: NSWorkspace.shared.isVoiceOverEnabled,
                        others: presets.compactMap { name, preset in
                            preset.tilingShortcut.map { TileBaseConflicts.NamedShortcut(name: name, shortcut: $0) }
                        } + [prompterPause] + (answerKeysOn ? approvalAnswers : []))
        }
    }

    /// The first note for `base`, or nil when the keys are free. Reads settings only; nothing is installed or
    /// prompted. `keys` is the live state unless a caller gives one.
    static func note(base: TileModifierBase, keymap: TileKeymap? = nil, keys: Keys? = nil) -> String? {
        let keys = keys ?? Keys.live()
        return TileBaseConflicts.notes(
            base: base, keymap: keymap ?? TileKeymap.defaults(base: base),
            talk: keys.talk, dictation: keys.dictation, pointing: keys.pointing, polyglot: keys.polyglot, chat: keys.chat,
            voiceOverOn: keys.voiceOverOn, others: keys.others).first
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
