import SwiftUI
import ZeusCore

struct PanelView: View {
    let connections: ConnectionsModel
    let permissions: PermissionsModel
    let preferences: Preferences
    let playDemo: () -> Void
    let openSetup: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                AvatarView(state: AvatarStatus.shared.current, size: 24)
                Text("ZEUS")
                    .font(Glass.font(15, .bold)).tracking(1.1)
                    .foregroundStyle(Theme.cloudPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("v\(ZeusCoreVersion.string)")
                    .font(Glass.caption)
                    .foregroundStyle(Theme.cloudQuiet)
                    .accessibilityLabel("Version \(ZeusCoreVersion.string)")
            }

            if !permissions.voiceReady {
                Button("Finish Setup…", action: openSetup)
                    .buttonStyle(ZeusButtonStyle(prominent: true))
            }

            Card(title: "Permissions") {
                if permissions.allGranted {
                    StatusRow(name: "All permissions are on", ok: true, detail: "")
                        .accessibilityElement(children: .combine)
                } else {
                    ForEach(PermissionsModel.Kind.allCases) { kind in
                        let on = permissions.granted[kind] == true
                        Button { permissions.open(kind) } label: {
                            StatusRow(name: kind.rawValue, ok: on, detail: on ? "On" : "Turn On…")
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("\(kind.rawValue): \(on ? "on" : "off")")
                        .accessibilityHint(on ? "Opens System Settings." : "Opens System Settings to turn it on.")
                    }
                }
            }

            Card(title: "Claude Code approvals") {
                StatusRow(name: "Approvals in the notch", ok: permissions.claudeHooksInstalled,
                          detail: permissions.claudeHooksInstalled ? "Connected" : "Off")
                    .accessibilityElement(children: .combine)
                Note(permissions.hookMessage
                     ?? (permissions.claudeHooksInstalled ? nil : "Adds ZEUS's hooks to ~/.claude/settings.json, with a backup. Your other hooks stay."))
                Button(permissions.claudeHooksInstalled ? "Disconnect" : "Connect Claude Code") {
                    if permissions.claudeHooksInstalled {
                        permissions.disconnectClaudeCode()
                    } else {
                        permissions.connectClaudeCode()
                    }
                }
                .buttonStyle(ZeusButtonStyle(prominent: !permissions.claudeHooksInstalled))
            }

            Card(title: "Chrome") {
                StatusRow(name: "Bridge", ok: permissions.chromeHostInstalled,
                          detail: permissions.chromeHostInstalled ? "Registered" : "Off")
                    .accessibilityElement(children: .combine)
                StatusRow(name: "Extension", ok: permissions.chromeConnected,
                          detail: permissions.chromeConnected ? "Connected" : "Not loaded")
                    .accessibilityElement(children: .combine)
                Note(permissions.chromeMessage)
                HStack {
                    Button(permissions.chromeHostInstalled ? "Disconnect" : "Connect Chrome") {
                        if permissions.chromeHostInstalled {
                            permissions.disconnectChrome()
                        } else {
                            permissions.connectChrome()
                        }
                    }
                    .buttonStyle(ZeusButtonStyle(prominent: !permissions.chromeHostInstalled))
                    if permissions.chromeHostInstalled && !permissions.chromeConnected {
                        Button("Show Extension…") { ChromeInstaller.showLoadUnpacked() }
                            .buttonStyle(ZeusButtonStyle(prominent: false))
                    }
                }
            }

            Card(title: "Brains") {
                // Details live in Settings › Connections; the panel only summarises.
                StatusRow(name: connections.foundNames.isEmpty ? "Looking for your CLIs…" : connections.foundNames.joined(separator: ", "),
                          ok: connections.foundCount > 0,
                          detail: "\(connections.foundCount) of \(connections.connections.count)")
                    .accessibilityElement(children: .combine)
            }

            // P0 item I ("Zeus next to the cursor"): a quick toggle here, in Settings and
            // `zeus debug presence on|off`, since all three write the same `presence.nearCursor`.
            Toggle("Show Zeus next to cursor", isOn: SettingsStore.shared.boolBinding(CursorPresenceController.settingID))
                .toggleStyle(.switch)
                .font(Glass.body)
                .foregroundStyle(Theme.cloudPrimary)
                .tint(Theme.accent)

            HStack(spacing: 8) {
                Button("Play Demo", action: playDemo)
                Spacer()
                Button("Settings…", action: openSettings)
                    .keyboardShortcut(",", modifiers: .command)
                Button("Quit ZEUS", action: quit)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(ZeusButtonStyle(prominent: false))
        }
        .padding(16)
        .frame(width: Theme.panelWidth)
        .background(GlassBackdrop().clipShape(RoundedRectangle(cornerRadius: Glass.cardRadius, style: .continuous)))
        .overlay(
            RoundedRectangle(cornerRadius: Glass.cardRadius, style: .continuous)
                .strokeBorder(Glass.hairline)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ZEUS")
    }
}

/// Real buttons for the dark panel: 28 pt tall, a press state, and a focus ring for keyboard use.
struct ZeusButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        ZeusButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct ZeusButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        // The shared glass pill: white when it is the main action, smoke otherwise.
        GlassButtonStyle(kind: prominent ? .primary : .secondary, compact: true).makeBody(configuration: configuration)
            .frame(minHeight: 28)
            .overlay(Capsule().strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: focused ? 2 : 0))
    }
}

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Glass.eyebrow).tracking(1.1)
                .foregroundStyle(Glass.tertiary)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: 18)
    }
}

private struct Note: View {
    let text: String?
    init(_ text: String?) { self.text = text }

    var body: some View {
        if let text {
            Text(text)
                .font(Glass.caption)
                .foregroundStyle(Glass.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// State is carried by the symbol's shape and the word, not only its colour.
private struct StatusRow: View {
    let name: String
    let ok: Bool
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? Theme.leaf : Theme.ember)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(name)
                .font(Glass.body)
                .foregroundStyle(Theme.cloudPrimary)
            Spacer()
            Text(detail)
                .font(Glass.font(11.5, ok ? .regular : .semibold))
                .foregroundStyle(ok ? Theme.cloudSecondary : Theme.ember)
        }
        .frame(minHeight: 22)
        .contentShape(Rectangle())
    }
}
