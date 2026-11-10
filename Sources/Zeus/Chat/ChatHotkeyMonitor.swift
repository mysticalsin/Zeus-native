import AppKit
import Carbon.HIToolbox
import SwiftUI
import ZeusCore

/// A system-wide shortcut for the chat window through Carbon's hot key API: no
/// Accessibility or Input Monitoring permission, and the key press never reaches other apps.
@MainActor
final class ChatHotkeyMonitor {
    static let shared = ChatHotkeyMonitor()

    private(set) var hotkey: ChatHotkey
    private(set) var problem: String?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: () -> Void = {}

    private init() {
        hotkey = ChatHotkey.stored(UserDefaults.standard.string(forKey: "chat.hotkey"))
    }

    func start(onPress: @escaping () -> Void) {
        self.onPress = onPress
        installHandler()
        register(hotkey)
    }

    func set(_ new: ChatHotkey) {
        hotkey = new
        UserDefaults.standard.set(new.rawValue, forKey: "chat.hotkey")
        register(new)
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { ChatHotkeyMonitor.shared.onPress() } }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func register(_ hotkey: ChatHotkey) {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        problem = nil
        guard let code = hotkey.keyCode else { return }
        let id = EventHotKeyID(signature: OSType(0x5A455553), id: 1) // "ZEUS"
        let status = RegisterEventHotKey(code, hotkey.modifiers.rawValue, id, GetApplicationEventTarget(), 0, &reference)
        if status != noErr {
            problem = "\(hotkey.symbols) is already used by another app. Pick another shortcut."
            reference = nil
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
