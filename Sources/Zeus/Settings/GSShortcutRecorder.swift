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
                .foregroundStyle(model.recording ? Color.white : (shortcut == nil ? GS.secondary : GS.controlText))
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 150)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(model.recording ? OB.controlAccentFill : GS.controlFill))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(model.recording ? OB.controlAccent : GS.controlStroke, lineWidth: model.recording ? 2 : 1))
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
    /// The key that stands in for Control+Option while VoiceOver is on (the talk key has one).
    var voiceOverFallback: Shortcut?
    let set: (Shortcut?) -> Void

    var body: some View {
        GSRow(symbol: symbol, title: title, text: text) {
            // One recorder style everywhere: the shortcut (or "Off") in a single control, and a menu beside it
            // with an explicit Off and Reset, instead of a loose "Off" pill that reads as a second button.
            HStack(spacing: 8) {
                ShortcutRecorderButton(shortcut: shortcut, onChange: { set($0) }, accessibilityName: title)
                if (allowsOff && shortcut != nil) || shortcut != defaultValue {
                    ShortcutOptionsMenu(title: title, canTurnOff: allowsOff && shortcut != nil,
                                        canReset: shortcut != defaultValue, defaultTitle: defaultValue?.title ?? "Off",
                                        off: { set(nil) }, reset: { set(defaultValue) })
                }
            }
        }
        if let shortcut {
            ForEach(ShortcutConflicts.warnings(for: shortcut, other: other, otherName: otherName,
                                               voiceOverOn: NSWorkspace.shared.isVoiceOverEnabled,
                                               voiceOverFallback: voiceOverFallback), id: \.self) { warning in
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

/// "More" menu for a shortcut: Turn off (when allowed) and Reset to the default. Snapshots draw the
/// glyph only, since offscreen renders cannot draw AppKit-backed menus.
struct ShortcutOptionsMenu: View {
    let title: String
    let canTurnOff: Bool
    let canReset: Bool
    let defaultTitle: String
    let off: () -> Void
    let reset: () -> Void

    var body: some View {
        if TopBarStyle.isSnapshot {
            glyph
        } else {
            Menu {
                if canTurnOff { Button("Turn off") { off() } }
                if canReset { Button("Reset to \(defaultTitle)") { reset() } }
            } label: { glyph }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Turn off or reset \(title)")
            .accessibilityLabel("\(title) options")
        }
    }

    private var glyph: some View {
        Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundStyle(GS.controlText)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GS.controlFill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(GS.controlStroke, lineWidth: 1))
    }
}

/// Where the key-access status lives: Permissions. Every other page links there instead of repeating it.
struct KeyAccessLinkRow: View {
    let navigation: GSNavigation
    var body: some View {
        GSLinkRow(symbol: "lock.shield", title: "Keys from other apps",
                  text: KeyListenAccess.granted ? "Zeus can see your shortcuts in every app." : "Zeus only sees shortcuts in its own windows until you allow access.",
                  destination: .permissions, navigation: navigation)
    }
}

/// A shortcut is set on the Shortcuts page only; this row shows its current value and links there.
struct ShortcutLinkRow: View {
    let symbol: String
    let title: String
    let current: Shortcut?
    let navigation: GSNavigation
    var body: some View {
        GSLinkRow(symbol: symbol, title: title, text: "Now: \(current?.title ?? "Off").", destination: .shortcuts, navigation: navigation)
    }
}
