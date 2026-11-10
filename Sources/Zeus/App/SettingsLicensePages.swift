import AppKit
import Observation
import SwiftUI
import ZeusCore

/// Drafts typed into the License and Assistant pages (never saved until you press Save or Activate).
@MainActor
@Observable
final class SecretDrafts {
    static let shared = SecretDrafts()
    var licenseKey = ""
    var keys: [AssistantAccount.Provider: String] = [:]
    var confirmSignOut = false
    var confirmDeactivate = false
    var note = ""
}

/// Assistant: account (your own keys, or ChatGPT sign-in later), model and behaviour.
struct AssistantSettings: View {
    let account: AssistantAccount
    let drafts: SecretDrafts
    private var store: SettingsStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: Glass.gap) {
            GlassCard(title: "Account") {
                GlassRow(title: account.isSignedIn ? "Signed in with your own keys" : "Not signed in",
                         note: account.isSignedIn ? account.saved.map(\.title).sorted().joined(separator: ", ") + " saved in the Keychain."
                                                  : "Add a key below, or sign in with ChatGPT when it arrives.",
                         icon: ("person.crop.circle.fill", Color(hex: 0x10A37F))) {
                    if account.isSignedIn {
                        Button(drafts.confirmSignOut ? "Press again" : "Sign out") {
                            if drafts.confirmSignOut { account.signOut(); drafts.confirmSignOut = false } else { drafts.confirmSignOut = true }
                        }
                        .buttonStyle(GlassButtonStyle(kind: .danger, compact: true))
                    }
                }
                GlassDivider()
                GlassRow(title: "Sign in with ChatGPT", note: "Use your ChatGPT plan instead of a key. Needs an OAuth service ZEUS does not run yet.") {
                    HStack(spacing: 6) {
                        GlassBadge(text: "Coming")
                        Button("Sign in") {}.buttonStyle(GlassButtonStyle(kind: .secondary, compact: true)).disabled(true).opacity(0.5)
                    }
                }
            }
            GlassCard(title: "Bring your own key") {
                ForEach(Array(AssistantAccount.Provider.allCases.enumerated()), id: \.element) { index, provider in
                    if index > 0 { GlassDivider() }
                    keyRow(provider)
                }
            }
            GlassCard(title: "Model") {
                GlassRow(title: "Provider", note: "Who answers in chat and drafts replies.") {
                    GlassSegmented(options: [("Claude CLI", "Claude CLI"), ("OpenAI", "OpenAI"), ("Anthropic", "Anthropic")],
                                   selection: store.stringBinding("assistant.provider"))
                }
                GlassDivider()
                GlassRow(title: "Model", note: modelNote) {
                    GlassMenu(options: models.map { ($0, $0) }, selection: Binding(get: { models.contains(store.string("assistant.model")) ? store.string("assistant.model") : models[0] },
                                                                              set: { store.set("assistant.model", $0) }))
                }
            }
        }
    }

    private var models: [String] {
        switch store.string("assistant.provider") {
        case "OpenAI": AssistantAccount.Provider.openAI.models
        case "Anthropic": AssistantAccount.Provider.anthropic.models
        default: ["Claude Code default"]
        }
    }

    private var modelNote: String {
        switch store.string("assistant.provider") {
        case "OpenAI": account.saved.contains(.openAI) ? "Uses your OpenAI key." : "Add an OpenAI key first."
        case "Anthropic": account.saved.contains(.anthropic) ? "Uses your Anthropic key." : "Add an Anthropic key first."
        default: "The Claude Code CLI on this Mac. No key needed."
        }
    }

    private func keyRow(_ provider: AssistantAccount.Provider) -> some View {
        let saved = account.saved.contains(provider)
        return GlassRow(title: provider.title, note: provider.use) {
            HStack(spacing: 6) {
                if saved {
                    GlassStatus(ok: true, text: "Saved in Keychain")
                    Button("Remove") { account.remove(provider) }.buttonStyle(GlassButtonStyle(kind: .quiet, compact: true))
                } else {
                    GlassSecureField(placeholder: provider.hint, text: Binding(get: { drafts.keys[provider] ?? "" }, set: { drafts.keys[provider] = $0 }), width: 200)
                    Button("Save") {
                        account.save(drafts.keys[provider] ?? "", for: provider)
                        drafts.keys[provider] = nil
                    }
                    .buttonStyle(GlassButtonStyle(kind: .primary, compact: true))
                    .disabled((drafts.keys[provider] ?? "").isEmpty)
                }
            }
        }
    }
}
