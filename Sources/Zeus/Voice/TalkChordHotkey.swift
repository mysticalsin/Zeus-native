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

/// The Carbon hot key that takes Control-Option-Space away from other apps and from the input-source shortcut while the
/// talk chord is active. Its handler does nothing: the press only has to be taken. The talk turn itself is read from the
/// key monitors, so a failed registration costs only a typed space (Settings says so).
@MainActor
final class TalkChordHotkey {
    static let shared = TalkChordHotkey()

    /// How the key reaches the system: injected in tests.
    struct Registrar {
        var register: (_ keyCode: UInt32, _ modifiers: UInt32) -> Bool
        var unregister: () -> Void
        static func carbon() -> Registrar { Registrar(register: { _, _ in false }, unregister: {}) }
    }

    static let problemText = "Another app uses Control-Option-Space. Hold Control + Option alone to talk."

    private(set) var problem: String?
    private(set) var isRegistered = false

    init(registrar: Registrar = .carbon()) {}

    /// Registers the chord, or lets go of it when it is nil. Idempotent.
    func sync(_ chord: Shortcut?) {}

    /// Lets go of the key while a recorder listens, and takes it back after.
    func setPaused(_ paused: Bool) {}

    /// Whether a hot key event with this signature is this one's to answer.
    nonisolated static func answers(signature: UInt32) -> Bool { false }
}
