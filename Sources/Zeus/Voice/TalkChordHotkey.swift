import AppKit
import Carbon.HIToolbox
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

/// STUB of the second talk key's live routing (docs/RIGHT-OPTION-TALK-PLAN.md).
@MainActor
enum SecondTalkRouting {
    static func current() -> (key: Shortcut?, yieldsTo: String?) { (.rightOption, nil) }
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

        /// The real Carbon registration, under the talk chord's own signature.
        static func carbon() -> Registrar {
            final class Box { var reference: EventHotKeyRef? }
            let box = Box()
            return Registrar(
                register: { code, modifiers in
                    installHandler()
                    let id = EventHotKeyID(signature: CarbonHotkeySignature.talkChord.rawValue, id: 1)
                    let status = RegisterEventHotKey(code, modifiers, id, GetApplicationEventTarget(), 0, &box.reference)
                    if status != noErr { box.reference = nil }
                    return status == noErr
                },
                unregister: {
                    if let reference = box.reference { UnregisterEventHotKey(reference) }
                    box.reference = nil
                })
        }

        private nonisolated(unsafe) static var handlerInstalled = false

        /// One handler, installed once. It answers only this hot key and does nothing with it: the press is only taken.
        private static func installHandler() {
            guard !handlerInstalled else { return }
            handlerInstalled = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                return TalkChordHotkey.answers(signature: hotKeyID.signature) ? noErr : OSStatus(eventNotHandledErr)
            }, 1, &spec, nil, nil)
        }
    }

    static let problemText = "Another app uses Control-Option-Space. Hold Control + Option alone to talk."

    private(set) var problem: String?
    private(set) var isRegistered = false
    private let registrar: Registrar
    private var desired: Shortcut?
    private var paused = false
    private var listening = true
    /// The chord last handed to the registrar. A chord that was refused is asked again on the next sync, since the holder
    /// that refused it (Chat or a shortcut being moved) may have let go since.
    private var attempted: Shortcut?

    init(registrar: Registrar = .carbon()) { self.registrar = registrar }

    /// Registers the chord, or lets go of it when it is nil. Idempotent. `listening` is whether the talk monitor can hear
    /// keys at all (Accessibility or Input Monitoring): without it a taken Space would be lost and nothing would talk.
    func sync(_ chord: Shortcut?, listening: Bool = true) {
        desired = chord
        self.listening = listening
        apply()
    }

    /// Lets go of the key while a recorder listens, and takes it back after.
    func setPaused(_ paused: Bool) {
        guard self.paused != paused else { return }
        self.paused = paused
        apply()
    }

    private func apply() {
        let want = paused || !listening ? nil : desired
        guard want != attempted || (want != nil && !isRegistered) else { return }
        if isRegistered { registrar.unregister() }
        isRegistered = false
        problem = nil
        attempted = want
        guard let want, let code = want.keyCode else { return }
        isRegistered = registrar.register(UInt32(code), Self.carbonModifiers(want.modifiers))
        if !isRegistered { problem = Self.problemText }
    }

    private static func carbonModifiers(_ modifiers: ShortcutModifiers) -> UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.control) { mask |= UInt32(controlKey) }
        if modifiers.contains(.option) { mask |= UInt32(optionKey) }
        if modifiers.contains(.shift) { mask |= UInt32(shiftKey) }
        if modifiers.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }

    /// Whether a hot key event with this signature is this one's to answer.
    nonisolated static func answers(signature: UInt32) -> Bool {
        CarbonHotkeySignature.owner(signature: signature) == .talkChord
    }
}
