import AppKit
import SwiftUI
import ZeusCore

private func toggle(_ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void, _ label: String) -> some View {
    GlassToggle(isOn: Binding(get: get, set: set), label: label)
}

private struct Paragraph: View {
    let text: String
    var body: some View {
        Text(text).font(Glass.body).foregroundStyle(Glass.text).fixedSize(horizontal: false, vertical: true)
    }
}

struct NotificationsSettings: View {
    let prefs: ExtraPreferences
    private var systemNotifications: SystemNotificationService { .shared }
    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "System alerts") {
                GlassRow(title: "Show system notifications",
                         note: systemNotifications.permissionNote,
                         icon: ("bell.badge.fill", Color(hex: 0xF43F5E))) {
                    HStack(spacing: 8) {
                        GlassToggle(isOn: Binding(
                            get: { SettingsStore.shared.bool("notify.system") },
                            set: { enabled in Task { await systemNotifications.setEnabledFromUserAction(enabled) } }
                        ), label: "System alerts")
                        if systemNotifications.authorization == .denied {
                            Button("Open Settings") { systemNotifications.openSystemSettingsAfterUserAction() }
                                .buttonStyle(GlassButtonStyle(kind: .secondary, compact: true))
                        }
                    }
                }
            }
            GlassCard(title: "Peek out of the notch") {
                GlassRow(title: "An agent needs you", note: "Approvals open as a card you can answer by voice or click.", icon: ("hand.raised.fill", Glass.warn)) {
                    toggle({ prefs.peekApprovals }, { prefs.peekApprovals = $0 }, "Approvals")
                }
                GlassDivider()
                GlassRow(title: "An agent finished", note: "A short card with what it did.", icon: ("checkmark.circle.fill", Glass.ok)) {
                    toggle({ prefs.peekAgentDone }, { prefs.peekAgentDone = $0 }, "Agent done")
                }
                GlassDivider()
                GlassRow(title: "Next meeting", note: "A heads-up with a Join button.", icon: ("calendar", Color(hex: 0xF43F5E))) {
                    GlassMenu(options: [(0, "Off"), (1, "1 min before"), (5, "5 min before"), (10, "10 min before"), (15, "15 min before")],
                              selection: Binding(get: { prefs.calendarLeadMinutes }, set: { prefs.calendarLeadMinutes = $0 }))
                }
                GlassDivider()
                GlassRow(title: "Reminders and to-dos due", icon: ("checklist", Color(hex: 0xF59E0B))) {
                    toggle({ prefs.peekReminders }, { prefs.peekReminders = $0 }, "Reminders")
                }
                GlassDivider()
                GlassRow(title: "Focus round over", icon: ("timer", Color(hex: 0x8B5CF6))) {
                    toggle({ prefs.peekFocusDone }, { prefs.peekFocusDone = $0 }, "Focus")
                }
            }
            GlassCard(title: "Quiet") {
                GlassRow(title: "Stay quiet while sharing or in full screen",
                         note: "Approvals still wait for you; they just don't pop open.") {
                    toggle({ prefs.quietWhileSharing }, { prefs.quietWhileSharing = $0 }, "Quiet while sharing")
                }
            }
        }
        .task { await systemNotifications.refreshAuthorization() }
    }
}

struct SoundsSettings: View {
    let prefs: ExtraPreferences
    let dictation: DictationSettings
    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Sounds") {
                GlassRow(title: "Play sounds") { toggle({ prefs.soundsOn }, { prefs.soundsOn = $0 }, "Sounds") }
                GlassDivider()
                GlassRow(title: "Volume") {
                    GlassStepper(value: Binding(get: { prefs.soundVolume }, set: { prefs.soundVolume = $0 }), range: 10...100,
                                 format: { "\($0)%" })
                }
            }
            GlassCard(title: "Moments") {
                row(.approval, { prefs.soundApproval }, { prefs.soundApproval = $0 })
                GlassDivider()
                row(.done, { prefs.soundDone }, { prefs.soundDone = $0 })
                GlassDivider()
                row(.todo, { prefs.soundTodo }, { prefs.soundTodo = $0 })
                GlassDivider()
                GlassRow(title: "Dictation start and stop", icon: ("mic.fill", Color(hex: 0x2F80ED))) {
                    toggle({ dictation.sounds }, { dictation.sounds = $0 }, "Dictation sounds")
                }
            }
        }
        .opacity(1)
    }

    private func row(_ event: ZeusSound.Event, _ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> some View {
        GlassRow(title: event.title, icon: ("speaker.wave.2.fill", Color(hex: 0xEC4899))) {
            HStack(spacing: 8) {
                Button { ZeusSound.play(event, force: true) } label: { Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(GlassButtonStyle(kind: .quiet, compact: true)).accessibilityLabel("Preview \(event.title)")
                toggle(get, set, event.title)
            }
        }
    }
}

struct ShortcutSettings: View {
    let prefs: ExtraPreferences
    let preferences: Preferences
    let dictation: DictationSettings
    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Hold to talk") {
                GlassRow(title: "Talk to ZEUS", note: dictation.enabled && dictation.key == preferences.pushToTalk ? "Double-tap, then speak." : "Hold, ask, let go.", icon: ("bolt.fill", Theme.bolt)) {
                    ShortcutRecorderButton(shortcut: preferences.pushToTalk, onChange: { preferences.chooseTalkKey($0) }, accessibilityName: "Talk key")
                }
                GlassDivider()
                GlassRow(title: "Dictate", note: dictation.key == nil ? "Off" : "Change it on the Dictation page.", icon: ("mic.fill", Color(hex: 0x2F80ED))) {
                    GlassStatus(ok: dictation.key != nil, text: dictation.key?.title ?? "Off")
                }
            }
            GlassCard(title: "Press anywhere") {
                GlassRow(title: "Open the notch", icon: ("rectangle.topthird.inset.filled", Color(hex: 0x3B82F6))) {
                    GlassMenu(options: ShortcutPreset.allCases.map { ($0, $0.title) },
                              selection: Binding(get: { prefs.openNotch }, set: { prefs.openNotch = $0 }))
                }
                GlassDivider()
                GlassRow(title: "Quick to-do", note: "Opens the To-do tab ready to type.", icon: ("checklist", Color(hex: 0xF59E0B))) {
                    GlassMenu(options: ShortcutPreset.allCases.map { ($0, $0.title) },
                              selection: Binding(get: { prefs.quickTodo }, set: { prefs.quickTodo = $0 }))
                }
                Text("If another app already uses a shortcut, pick a different one.").font(Glass.caption).foregroundStyle(Glass.secondary)
            }
        }
    }
}

struct InterviewSettings: View {
    let prefs: ExtraPreferences
    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Screen sharing") {
                GlassRow(title: "Hide ZEUS from screen sharing and recordings",
                         note: "The notch, cards, settings and the bolt stay visible to you but not to the people watching.",
                         icon: ("eye.slash.fill", Color(hex: 0x14B8A6))) {
                    toggle({ prefs.hideFromScreenShare }, { prefs.hideFromScreenShare = $0 }, "Hide from sharing")
                }
                GlassDivider()
                GlassRow(title: "Teleprompter", note: "Always hidden from shares while it runs.", icon: ("text.alignleft", Color(hex: 0x6366F1))) {
                    GlassStatus(ok: true, text: "Always")
                }
            }
            GlassCard(title: "Interview helper") {
                Paragraph(text: "Live hints during a call are not built yet. Whether ZEUS should listen to the other side of a call is still an open question, so nothing here records anyone.")
            }
        }
    }
}

struct IPhoneSettings: View {
    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard {
                HStack(spacing: 16) {
                    GlassIcon(symbol: "iphone", tint: Color(hex: 0x94A3B8), size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Needs the ZEUS iPhone app").font(Glass.title).foregroundStyle(Glass.text)
                        Text("There is no iPhone app yet, so there is nothing to pair.").font(Glass.body).foregroundStyle(Glass.secondary)
                    }
                    Spacer()
                    GlassStatus(ok: false, text: "Not available")
                }
            }
            GlassCard(title: "Design note") {
                Paragraph(text: "Pairing would happen on your own network: the Mac shows a short code, the phone types it, and the two talk directly. Nothing goes through a ZEUS server.")
                GlassDivider()
                Paragraph(text: "First things on the phone: answer agent approvals, add and check to-dos, and see what your agents are doing.")
            }
        }
    }
}

struct DiagnosticsSettings: View {
    let permissions: PermissionsModel?
    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "This Mac") {
                let rows = Diagnostics.lines(permissions: permissions)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { GlassDivider() }
                    GlassRow(title: row.0) {
                        Text(row.1).font(Glass.font(12, .medium)).foregroundStyle(Glass.secondary).lineLimit(1)
                    }
                }
            }
            EnergyCard()
            GlassCard(title: "Share") {
                GlassRow(title: "Copy diagnostics", note: "Versions and on/off states only. No keys, no file contents, your home folder shows as ~.") {
                    HStack(spacing: 8) {
                        Button("Open Folder") { NSWorkspace.shared.open(ZeusPaths.supportDirectory) }
                            .buttonStyle(GlassButtonStyle(kind: .secondary, compact: true))
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Diagnostics.report(permissions: permissions), forType: .string)
                        }
                        .buttonStyle(GlassButtonStyle(kind: .primary, compact: true))
                    }
                }
            }
        }
    }
}
