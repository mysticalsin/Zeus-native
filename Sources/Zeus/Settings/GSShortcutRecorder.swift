import AppKit
import SwiftUI
import ZeusCore

/// A real shortcut recorder: click it, press any chord, and it saves. Modifier-only chords
/// (Option+Command, Right Command, Fn, Control+Option) are recorded when you let go; a key with
/// modifiers (⌥Space, ⌃⌥Z) is recorded the moment you press it. Escape cancels.
@MainActor
final class ShortcutRecorderModel: ObservableObject {
    @Published var recording = false
    @Published var preview = ""
    private var monitor: Any?
    private var state = ShortcutRecorderState()
    private var onCapture: ((Shortcut) -> Void)?

    func begin(onCapture: @escaping (Shortcut) -> Void) {
        end()
        self.onCapture = onCapture
        state = ShortcutRecorderState()
        recording = true
        preview = ""
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            guard let self, let converted = Self.convert(event) else { return event }
            let swallow = MainActor.assumeIsolated { self.handle(converted) }
            return swallow ? nil : event
        }
    }

    func end() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        preview = ""
    }

    private nonisolated static func convert(_ event: NSEvent) -> ShortcutEvent?? {
        let mods = ShortcutModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        switch event.type {
        case .flagsChanged: return .some(.flags(keyCode: event.keyCode, modifiers: mods))
        case .keyDown: return event.isARepeat ? .some(nil) : .some(.keyDown(keyCode: event.keyCode, modifiers: mods))
        case .keyUp: return .some(.keyUp(keyCode: event.keyCode))
        default: return nil
        }
    }

    /// True when the event was ours (swallowed so it doesn't beep or type). A repeat is swallowed, not fed.
    private func handle(_ maybe: ShortcutEvent?) -> Bool {
        guard let converted = maybe else { return true }
        switch state.feed(converted) {
        case .captured(let shortcut)?:
            let done = onCapture
            end()
            done?(shortcut)
        case .cancelled?:
            end()
        case nil:
            let held = state.preview
            preview = held.isEmpty ? "" : Shortcut(modifiers: held).symbol + "\u{2026}"
        }
        return true
    }
}

/// The recorder button itself.
struct ShortcutRecorderButton: View {
    let shortcut: Shortcut?
    let onChange: (Shortcut) -> Void
    var accessibilityName = "Shortcut"
    @StateObject private var model = ShortcutRecorderModel()

    var body: some View {
        Button {
            if model.recording { model.end() } else { model.begin(onCapture: onChange) }
        } label: {
            Text(label)
                .font(OB.font(14, .semibold))
                .foregroundStyle(model.recording ? Color.white : GS.text)
                .lineLimit(1)
                .frame(minWidth: 150)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(model.recording ? OB.blue : GS.buttonFill))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(model.recording ? OB.blue : GS.buttonStroke, lineWidth: model.recording ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityName): \(shortcut?.title ?? "Off"). Click, then press the shortcut you want.")
        .onDisappear { model.end() }
    }

    private var label: String {
        if model.recording { return model.preview.isEmpty ? "Press the shortcut\u{2026}" : model.preview }
        return shortcut?.title ?? "Off"
    }
}

/// One Settings row: name, recorder, Reset (and Turn off when allowed), warnings underneath.
struct ShortcutRecorderRow: View {
    let symbol: String
    let title: String
    let text: String
    let shortcut: Shortcut?
    let defaultValue: Shortcut?
    var allowsOff = false
    var otherName = ""
    var other: Shortcut?
    let set: (Shortcut?) -> Void

    var body: some View {
        GSRow(symbol: symbol, title: title, text: text) {
            HStack(spacing: 8) {
                ShortcutRecorderButton(shortcut: shortcut, onChange: { set($0) }, accessibilityName: title)
                if allowsOff, shortcut != nil {
                    Button("Off") { set(nil) }.buttonStyle(GSButtonStyle()).accessibilityLabel("Turn \(title) off")
                }
                if shortcut != defaultValue {
                    Button("Reset") { set(defaultValue) }.buttonStyle(GSButtonStyle()).accessibilityLabel("Reset \(title) to \(defaultValue?.title ?? "Off")")
                }
            }
        }
        if let shortcut {
            ForEach(ShortcutConflicts.warnings(for: shortcut, other: other, otherName: otherName), id: \.self) { warning in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 11.5))
                    Text(warning).font(OB.font(13)).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.ember)
                .padding(.vertical, 6)
            }
        }
    }
}

/// Where the shortcuts get their keys: Accessibility or Input Monitoring.
struct KeyAccessRow: View {
    var body: some View {
        GSRow(symbol: "lock.shield", title: "Keys from other apps",
              text: KeyListenAccess.granted
                ? "Zeus can see your shortcuts in every app."
                : "Zeus can only see shortcuts while its own windows are in front. Allow Input Monitoring or Accessibility.") {
            HStack(spacing: 10) {
                GSStatus(ok: KeyListenAccess.granted,
                         text: KeyListenAccess.granted ? (KeyListenAccess.accessibility ? "Accessibility on" : "Input Monitoring on") : "Not allowed")
                if !KeyListenAccess.granted {
                    Button("Input Monitoring") { KeyListenAccess.requestInputMonitoring() }.buttonStyle(GSButtonStyle(prominent: true))
                    Button("Accessibility") {
                        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                    }.buttonStyle(GSButtonStyle())
                }
            }
        }
    }
}
