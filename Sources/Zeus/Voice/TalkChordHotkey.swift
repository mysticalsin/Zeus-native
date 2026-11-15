import AppKit
import ZeusCore

/// Which Carbon shortcuts hold Control-Option-Space right now, and so whether the talk chord is on (docs/ULTRON-CHORD-PLAN.md).
/// A Carbon choice always beats the chord, so there is exactly one owner and it is decided ahead of time.
@MainActor
enum TalkChordRouting {
    /// Chat, the agent picker and Quick to-do: the Carbon shortcuts a person can put on Control-Option-Space.
    static func holders() -> [(name: String, shortcut: Shortcut?)] {
        let extras = ExtraPreferences.shared
        return [("Chat", ChatHotkeyMonitor.shared.hotkey.shortcut),
                ("Agent picker", extras.openNotch.tilingShortcut),
                ("Quick to-do", extras.quickTodo.tilingShortcut)]
    }

    /// The chord for the talk key as heard, or nil with the name of the holder that keeps Control-Option-Space.
    static func current(heard: Shortcut?, shared: Bool) -> (chord: Shortcut?, heldBy: String?) {
        guard let heard else { return (nil, nil) }
        return VoiceKey.talkChord(heard: heard, shared: shared, voiceOverOn: NSWorkspace.shared.isVoiceOverEnabled,
                                  holders: holders())
    }
}
