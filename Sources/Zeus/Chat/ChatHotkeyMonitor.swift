import AppKit
import Carbon.HIToolbox
import SwiftUI
import ZeusCore

/// A system-wide shortcut for the chat window through Carbon's hot key API: no
/// Accessibility or Input Monitoring permission, and the key press never reaches other apps.
@MainActor
final class ChatHotkeyMonitor {
    static let shared = ChatHotkeyMonitor()

    /// How a key reaches the system: injected in tests.
    struct Ops {
        var register: (_ keyCode: UInt32, _ modifiers: UInt32) -> Bool
        var unregister: () -> Void

        /// The real Carbon registration, under Chat's own signature.
        static func carbon() -> Ops {
            final class Box { var reference: EventHotKeyRef? }
            let box = Box()
            return Ops(
                register: { code, modifiers in
                    let id = EventHotKeyID(signature: CarbonHotkeySignature.chat.rawValue, id: 1)
                    let status = RegisterEventHotKey(code, modifiers, id, GetApplicationEventTarget(), 0, &box.reference)
                    if status != noErr { box.reference = nil }
                    return status == noErr
                },
                unregister: {
                    if let reference = box.reference { UnregisterEventHotKey(reference) }
                    box.reference = nil
                })
        }
    }

    private(set) var hotkey: ChatHotkey
    private(set) var problem: String?
    private let ops: Ops
    private let defaults: UserDefaults
    private var handler: EventHandlerRef?
    private var paused = false
    var onPress: () -> Void = {}
    /// Called after the choice changes, so the talk chord can yield to it or take Control-Option-Space back.
    var onChange: () -> Void = {}

    private convenience init() {
        let defaults = UserDefaults.standard
        self.init(hotkey: ChatHotkey.stored(defaults.string(forKey: "chat.hotkey")), defaults: defaults, ops: .carbon())
    }

    init(hotkey: ChatHotkey, defaults: UserDefaults, ops: Ops) {
        self.hotkey = hotkey
        self.defaults = defaults
        self.ops = ops
    }

    func start(onPress: @escaping () -> Void) {
        self.onPress = onPress
        installHandler()
        register(hotkey)
    }

    func set(_ new: ChatHotkey) {
        hotkey = new
        defaults.set(new.rawValue, forKey: "chat.hotkey")
        // The old key goes first and the talk chord hears of the change before the new key is asked for: moving Chat onto
        // Control-Option-Space fails while the chord still holds it, and moving it off lets the chord take the key at once.
        ops.unregister()
        onChange()
        register(new)
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            // Answer only Chat's own hot key; any other Zeus hot key belongs to another handler.
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard CarbonHotkeySignature.owner(signature: hotKeyID.signature) == .chat else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { MainActor.assumeIsolated { ChatHotkeyMonitor.shared.onPress() } }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    /// Lets go of the hot key while a recorder is listening, so the key reaches the window, and takes it back after.
    func setPaused(_ paused: Bool) {
        guard self.paused != paused else { return }
        self.paused = paused
        ops.unregister()
        register(hotkey)
    }

    /// Asks for the key; whatever held the old one has already been let go.
    private func register(_ hotkey: ChatHotkey) {
        problem = nil
        guard !paused, let code = hotkey.keyCode else { return }
        if !ops.register(code, hotkey.modifiers.rawValue) {
            problem = "\(hotkey.symbols) is already used by another app. Pick another shortcut."
        }
    }
}

/// Settings › General › Chat.
struct ChatHotkeySection: View {
    let monitor = ChatHotkeyMonitor.shared
    let state = ChatHotkeySectionState.shared

    var body: some View {
        Section("Chat") {
            Picker("Open the chat window", selection: Binding(get: { state.hotkey }, set: { state.hotkey = $0; monitor.set($0); state.problem = monitor.problem })) {
                ForEach(ChatHotkey.allCases) { key in
                    Text(key.symbols).tag(key).accessibilityLabel(key.spoken)
                }
            }
            if let problem = state.problem {
                Text(problem).font(.callout).foregroundStyle(.red)
            } else {
                Text("Works from any app. Press Escape to hide the window again.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// Mirrors the monitor for SwiftUI (the monitor itself is not observable).
@MainActor
@Observable
final class ChatHotkeySectionState {
    static let shared = ChatHotkeySectionState()
    var hotkey = ChatHotkeyMonitor.shared.hotkey
    var problem = ChatHotkeyMonitor.shared.problem
}
