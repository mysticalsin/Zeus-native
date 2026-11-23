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

/// The second talk key as the talk monitor listens on it right now (docs/RIGHT-OPTION-TALK-PLAN.md): the stored key, or Right
/// Option when the owner chose nothing, unless a key chosen elsewhere has it (`VoiceKey.secondTalkKey`). Reads the settings and
/// the Carbon holders, writes nothing.
@MainActor
enum SecondTalkRouting {
    /// The key at the last sync point, for the readers that run on every event (pointing). Nil until the app has synced.
    static var lastSynced: Shortcut?

    static func current() -> (key: Shortcut?, yieldsTo: String?) {
        let dictation = DictationSettings.shared
        let dictationKey = dictation.enabled ? dictation.key : nil
        let pointing = PointingSettings.enabled ? PointingSettings.shortcut : nil
        let polyglot = PolyglotSettings.shared
        let voiceOverOn = NSWorkspace.shared.isVoiceOverEnabled
        let heard = VoiceKey.effectiveTalkKey(chosen: Preferences.shared.pushToTalk, dictation: dictationKey, pointing: pointing,
                                              voiceOverOn: voiceOverOn)
        let stored = ShortcutStore.loadSecondTalk(.standard)
        return VoiceKey.secondTalkKey(chosen: stored.key, explicit: stored.explicit, heard: heard, dictation: dictationKey,
                                      pointing: pointing, polyglot: polyglot.enabled ? polyglot.hotkey : nil,
                                      voiceOverOn: voiceOverOn, carbonHolders: TalkChordRouting.holders())
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
    private let registrar: Registrar
    private var registration = TalkChordRegistration()

    var isRegistered: Bool {
        if case .holding = registration.state { return true }
        return false
    }

    init(registrar: Registrar = .carbon()) { self.registrar = registrar }

    /// Registers the chord, or lets go of it when it is nil. Idempotent. `listening` is whether the talk monitor can hear
    /// keys at all (Accessibility or Input Monitoring): without it a taken Space would be lost and nothing would talk.
    func sync(_ chord: Shortcut?, listening: Bool = true) {
        let before = registration.state
        let effects = registration.sync(chord, listening: listening)
        perform(effects, changed: registration.state != before)
    }

    /// Lets go of the key while a recorder listens, and takes it back after.
    func setPaused(_ paused: Bool) {
        let before = registration.state
        let effects = paused ? registration.pause() : registration.resume()
        perform(effects, changed: registration.state != before)
    }

    private func perform(_ effects: [TalkChordRegistration.Effect], changed: Bool) {
        guard changed || !effects.isEmpty else { return }
        problem = nil
        for effect in effects {
            switch effect {
            case .unregister:
                registrar.unregister()
            case .register(let chord):
                guard let code = chord.keyCode else {
                    registration.noteRegistered(false)
                    return
                }
                let registered = registrar.register(UInt32(code), Self.carbonModifiers(chord.modifiers))
                registration.noteRegistered(registered)
                if !registered { problem = Self.problemText }
            }
        }
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
