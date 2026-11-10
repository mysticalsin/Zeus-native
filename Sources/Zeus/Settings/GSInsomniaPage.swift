import SwiftUI
import ZeusCore

/// Drafts for the Insomnia page (this toolchain has no SwiftUI `@State` macro).
@MainActor
@Observable
final class InsomniaPageState {
    static let shared = InsomniaPageState()
    var passwordDraft = ""
    var pickerOpen = false
    var running: [InsomniaController.AppChoice] = []
}

/// Settings > Insomnia: the lid-closed admin rule, what happens when the lid closes, the hotspot
/// and agent nudges. Session length, battery and heat rules stay on the Keep awake card in General.
@MainActor
struct InsomniaSettingsPage: View {
    private var insomnia: InsomniaController { .shared }
    private var page: InsomniaPageState { .shared }

    var body: some View {
        GSPageHeading(section: .insomnia, subtitle: "Close the lid. Your agents keep working.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Lid-closed mode") {
            GSRow(symbol: "lock.shield", title: "Admin rule", text: insomnia.setup.text) {
                HStack(spacing: 10) {
                    GSStatus(ok: insomnia.setup.isReady, text: insomnia.setup.isReady ? "Set up" : "Not set up")
                    if insomnia.setup.isReady {
                        Button("Remove", action: insomnia.uninstallRule).buttonStyle(GSButtonStyle()).disabled(insomnia.setupBusy)
                    } else {
                        Button(insomnia.setupBusy ? "Waiting…" : "Set up", action: insomnia.installRule)
                            .buttonStyle(GSButtonStyle(prominent: true)).disabled(insomnia.setupBusy)
                    }
                }
            }
            if let message = insomnia.setupMessage { GSInfo(text: message) }
            GSInfo(text: "Set up asks macOS for your password once; Zeus never sees it. It adds \(InsomniaSudoers.path), which lets only your account run exactly four commands: pmset disablesleep 1 and 0, and lowpowermode 1 and 0. It also adds a small launchd agent that puts sleep back within a minute if Zeus quits or crashes mid-session.")
            GSDivider()
            GSToggleRow(symbol: "laptopcomputer", title: "Keep working with the lid closed", text: "Insomnia sessions keep the Mac awake with the lid shut. Ending one, by hand, time, battery or heat, always puts sleep back.",
                        isOn: Binding(get: { insomnia.lidClosedMode }, set: { insomnia.lidClosedMode = $0 }))
        }
        GSCard("When the lid closes") {
            GSToggleRow(symbol: "speaker.slash", title: "Mute the sound", text: "The volume comes back when you open the lid.",
                        isOn: Binding(get: { insomnia.muteOnClose }, set: { insomnia.muteOnClose = $0 }))
            GSDivider()
            GSToggleRow(symbol: "leaf", title: "Low Power Mode on battery", text: "Switched on with the admin rule, and back as it was when the lid opens.",
                        isOn: Binding(get: { insomnia.lowPowerOnBattery }, set: { insomnia.lowPowerOnBattery = $0 }))
            GSDivider()
            GSRow(symbol: "snowflake", title: "Freeze these apps", text: "Paused while the lid is closed, resumed when it opens. Zeus, terminals, editors and agents are never frozen.") {
                Button(page.pickerOpen ? "Done" : "Add from running apps") {
                    page.running = insomnia.freezableRunningApps()
                    page.pickerOpen.toggle()
                }
                .buttonStyle(GSButtonStyle())
            }
            if insomnia.freezeBundleIDs.isEmpty, !page.pickerOpen {
                GSInfo(text: "No apps yet. Chat apps like Slack or Discord are good picks.")
            }
            ForEach(insomnia.freezeBundleIDs, id: \.self) { id in
                HStack {
                    Text(name(for: id)).font(GS.rowText).foregroundStyle(GS.text)
                    Text(id).font(OB.font(12)).foregroundStyle(GS.secondary)
                    Spacer()
                    Button("Remove") { insomnia.toggleFreeze(id) }.buttonStyle(GSButtonStyle())
                }
                .padding(.leading, 42).padding(.vertical, 4)
            }
            if page.pickerOpen {
                ForEach(page.running.filter { !insomnia.freezeBundleIDs.contains($0.bundleID) }) { app in
                    HStack {
                        Text(app.name).font(GS.rowText).foregroundStyle(GS.text)
                        Text(app.bundleID).font(OB.font(12)).foregroundStyle(GS.secondary)
                        Spacer()
                        Button("Add") { insomnia.toggleFreeze(app.bundleID) }.buttonStyle(GSButtonStyle())
                    }
                    .padding(.leading, 42).padding(.vertical, 4)
                }
            }
        }
        GSCard("Hotspot") {
            GSRow(symbol: "personalhotspot", title: "iPhone hotspot", text: "If the network drops while the lid is closed, Zeus tries to join it. macOS needs Location access for Zeus to see Wi-Fi names.") {
                field("iPhone name", text: Binding(get: { insomnia.hotspotSSID }, set: { insomnia.hotspotSSID = $0 }))
            }
            GSDivider()
            GSRow(symbol: "key", title: "Hotspot password", text: insomnia.hasHotspotPassword ? "Saved in your Keychain, never in a file." : "Optional. Kept in your Keychain only; without it Zeus uses the password macOS already knows.") {
                HStack(spacing: 10) {
                    SecureField(insomnia.hasHotspotPassword ? "Saved" : "Password", text: Binding(get: { page.passwordDraft }, set: { page.passwordDraft = $0 }))
                        .textFieldStyle(.plain)
                        .snapshotSafeText(page.passwordDraft, placeholder: insomnia.hasHotspotPassword ? "Saved" : "Password", secure: true)
                        .font(OB.font(13.5)).foregroundStyle(GS.text)
                        .padding(.horizontal, 10).frame(width: 150, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                        .accessibilityLabel("Hotspot password")
                        .onSubmit(savePassword)
                    Button("Save", action: savePassword).buttonStyle(GSButtonStyle()).disabled(page.passwordDraft.isEmpty)
                    if insomnia.hasHotspotPassword {
                        Button("Remove") { insomnia.saveHotspotPassword("") }.buttonStyle(GSButtonStyle())
                    }
                }
            }
        }
        GSCard("Agents in tmux") {
            GSToggleRow(symbol: "arrow.uturn.right", title: "Nudge stalled agents", text: "Every 2 minutes Zeus looks at tmux panes running claude, codex, gemini, cursor-agent or node. One that has not changed for the time below gets \"continue\" and Enter, once per stall. Plain shells are never touched.",
                        isOn: Binding(get: { insomnia.nudgeAgents }, set: { insomnia.nudgeAgents = $0 }))
            GSDivider()
            GSRow(symbol: "hourglass", title: "Stalled after", text: "How long a pane must sit still before the nudge.") {
                GSPopup(selection: Binding(get: { "\(insomnia.nudgeMinutes) min" },
                                           set: { insomnia.nudgeMinutes = Int($0.split(separator: " ").first ?? "") ?? 10 }),
                        options: InsomniaController.nudgeChoices.map { "\($0) min" })
            }
        }
    }

    private func savePassword() {
        // Return in an empty field must not remove the saved password; Remove is the only way to delete it.
        guard !page.passwordDraft.isEmpty else { return }
        if insomnia.saveHotspotPassword(page.passwordDraft) { page.passwordDraft = "" }
    }

    private func name(for bundleID: String) -> String {
        page.running.first { $0.bundleID == bundleID }?.name
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path) }
            ?? bundleID
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .snapshotSafeText(text.wrappedValue, placeholder: placeholder)
            .font(OB.font(13.5)).foregroundStyle(GS.text)
            .padding(.horizontal, 10).frame(width: 170, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
            .accessibilityLabel(placeholder)
    }
}
