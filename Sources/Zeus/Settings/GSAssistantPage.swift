import SwiftUI

/// Settings › Assistant. Sensitive switches stay off until the owner turns them on.
/// Pointing itself keeps the catalog default, which is already on.
struct AssistantSettingsPage: View {
    private var store: SettingsStore { .shared }
    @State private var drafts: [AssistantAccount.Provider: String] = [:]

    var body: some View {
        GSPageHeading(section: .assistant, subtitle: "Pointing, visual explanation, and the keys they use. Sensitive switches stay off until you turn them on.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Keys") {
            keyRow(.openAI)
            GSDivider()
            keyRow(.anthropic)
            GSInfo(text: "A key is saved in the Keychain only when you press Save. The field starts empty.")
        }
        GSCard("Visual explanation") {
            GSToggleRow(symbol: "square.on.circle", title: "Enable visual explanations",
                        text: "Off until you turn it on. Nothing is captured until you use the explanation window.",
                        isOn: store.boolBinding("explanation.enabled"))
            GSDivider()
            choice("explanation.shortcut", label: "Spoken request shortcut")
        }
        GSCard("Desktop pointing") {
            GSToggleRow(symbol: "cursorarrow.rays", title: "Enable desktop pointing",
                        text: "Hold the pointing keys and ask about what is under the pointer.",
                        isOn: store.boolBinding("pointing.enabled"))
            GSDivider()
            GSToggleRow(symbol: "scribble", title: "Draw while held",
                        text: "While the pointing keys are held, the pointer leaves a trail.",
                        isOn: store.boolBinding("pointing.drawWhileHeld"))
            GSDivider()
            GSToggleRow(symbol: "photo", title: "Send a screenshot with each question",
                        text: "Off until you turn it on. One capture goes to the provider you picked and is not saved.",
                        isOn: store.boolBinding("pointing.sendScreenshot"))
            GSDivider()
            choice("pointing.shortcut", label: "Pointing keys")
            GSDivider()
            choice("pointing.provider", label: "Provider")
            GSDivider()
            GSToggleRow(symbol: "keyboard", title: "Double-tap Control to type a question",
                        text: "Off until you turn it on.",
                        isOn: store.boolBinding("pointing.textEntry"))
            GSDivider()
            GSToggleRow(symbol: "fn", title: "Use Fn and Control for dictation",
                        text: "Off until you turn it on. Turning it off puts the previous dictation key back.",
                        isOn: store.boolBinding("pointing.dictationFnControl"))
        }
        GSCard("Which AI answers") {
            RouterSettingsView()
        }
    }

    private func choice(_ id: String, label: String) -> some View {
        GSPopup(selection: store.stringBinding(id), options: SettingsCatalog.option(id)?.choices ?? [])
            .accessibilityLabel(label)
    }

    private func keyRow(_ provider: AssistantAccount.Provider) -> some View {
        let saved = AssistantAccount.shared.saved.contains(provider)
        return GSRow(symbol: "key", title: provider.title, text: saved ? "Saved in the Keychain." : "Empty until you paste a key and save it.") {
            HStack(spacing: 8) {
                SecureField(saved ? "Saved" : "Paste a key", text: Binding(get: { drafts[provider] ?? "" }, set: { drafts[provider] = $0 }))
                    .textFieldStyle(.plain)
                    .frame(width: 180)
                    .accessibilityLabel("\(provider.title) key")
                Button("Save") {
                    let text = drafts[provider] ?? ""
                    if AssistantAccount.shared.save(text, for: provider) { drafts[provider] = "" }
                }
                .buttonStyle(GSButtonStyle())
                .disabled((drafts[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if saved {
                    Button("Remove") { _ = AssistantAccount.shared.remove(provider) }
                        .buttonStyle(GSButtonStyle())
                }
            }
        }
    }
}
