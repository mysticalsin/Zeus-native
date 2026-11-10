import AppKit
import SwiftUI
import ZeusCore

/// Settings > Integrations: every AI Zeus can follow or hand work to, each with its own mark,
/// Connect, Check again, a status and "Offer for new chats". Installed tools are found by looking
/// for files and local ports only.
struct AIConnectionsPage: View {
    let context: GSContext
    private var model: AIConnections { AIConnections.shared }
    private var services: OnboardingServices { context.services }

    var body: some View {
        GSPageHeading(section: .integrations, subtitle: "Your agents, followed from the notch.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Agents") {
            ForEach(Array([AIProvider.claudeCode, .codex, .cursor, .gemini].enumerated()), id: \.element) { index, provider in
                if index > 0 { GSDivider() }
                connection(provider)
            }
            if let message = services.connectMessage { GSInfo(text: message) }
        }
        GSCard("Apps") {
            connection(.chatgpt)
            GSDivider()
            connection(.grok)
        }
        GSCard("On this Mac") {
            connection(.ollama)
            GSDivider()
            connection(.lmStudio)
            GSInfo(text: "Local models never send a word off this Mac.")
        }
        AnyLLMCard(services: services)
        GSCard("Available apps") {
            let shown = AIProvider.allCases.filter { provider in
                // Any LLM is offered only once its endpoint passed a test.
                if provider == .anyLLM, case .connected = model.status(provider, services: services) { return true }
                if provider == .anyLLM { return false }
                return model.installed(provider) || model.status(provider, services: services) != .notInstalled
            }
            ForEach(Array(shown.enumerated()), id: \.element) { index, provider in
                if index > 0 { GSDivider() }
                HStack(spacing: 0) {
                    BrandMark(provider: provider, side: 26).frame(width: 42, alignment: .leading).accessibilityHidden(true)
                    GSToggleRow(title: "Offer \(provider.title) for new chats",
                                isOn: Binding(get: { model.offers(provider) }, set: { model.setOffers(provider, $0) }))
                }
            }
        }
        .task { await model.refresh(); await model.checkAllSignIns() }
    }

    private func connection(_ provider: AIProvider) -> some View {
        let step = model.step(provider, services: services)
        let connected = step == .connected
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                BrandMark(provider: provider, side: 26).frame(width: 42, alignment: .leading).accessibilityHidden(true)
                GSRow(title: provider.title, text: model.detail(provider, services: services)) {
                    HStack(spacing: 10) {
                        if connected { GSStatus(ok: true, text: "Connected") }
                        else if step == .install { GSStatus(ok: false, text: "Not found") }
                        if model.busy.contains(provider) {
                            ProgressView().controlSize(.small)
                        } else if !connected {
                            // One button that does the next thing: Install, Sign in, Connect, Open or Start.
                            Button(step.buttonTitle) { model.primary(provider, services: services) }
                                .buttonStyle(GSButtonStyle(prominent: true))
                                .accessibilityLabel("\(step.buttonTitle) \(provider.title)")
                        } else if provider.kind == .hooked {
                            Button("Repair") { Task { await model.connectAndCheck(provider, services: services) } }
                                .buttonStyle(GSButtonStyle())
                                .accessibilityLabel("Repair \(provider.title)")
                        } else if model.canDisconnect(provider) {
                            Button("Disconnect") { model.disconnect(provider, services: services) }
                                .buttonStyle(GSButtonStyle())
                                .accessibilityLabel("Disconnect \(provider.title)")
                        }
                        Button("Check again") {
                            context.refresh()
                            Task { await model.refresh(); if provider.kind == .hooked { await model.checkSignIn(provider) } }
                        }
                        .buttonStyle(GSButtonStyle())
                        .accessibilityLabel("Check \(provider.title) again")
                    }
                }
            }
            if step == .install, model.installShown == provider { InstallRow(provider: provider) }
        }
    }
}

/// Under a missing tool: the official install command to copy (Zeus never runs it) and the docs.
private struct InstallRow: View {
    let provider: AIProvider

    var body: some View {
        GSRow(title: "Install", text: AIConnectFlow.installCommand(provider) ?? "Get it from the official download page.") {
            HStack(spacing: 10) {
                if let command = AIConnectFlow.installCommand(provider) {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        AIConnections.shared.messages[provider] = "Copied. Paste it in Terminal, then click Check again."
                    }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel("Copy the \(provider.title) install command")
                }
                if let docs = AIConnectFlow.docsURL(provider) {
                    Button("Docs") { NSWorkspace.shared.open(docs) }
                        .buttonStyle(GSButtonStyle())
                        .accessibilityLabel("Open the \(provider.title) install guide")
                }
            }
        }
        .textSelection(.enabled)
        .padding(.leading, 42)
    }
}

/// The "Any LLM" card: an OpenAI compatible endpoint. The key goes to the Keychain once and is
/// never shown again.
private struct AnyLLMCard: View {
    let services: OnboardingServices
    private var model: AIConnections { AIConnections.shared }
    private var key: String { model.keyDraft }

    var body: some View {
        GSCard("Any LLM") {
            HStack(spacing: 0) {
                BrandMark(provider: .anyLLM, side: 26).frame(width: 42, alignment: .leading).accessibilityHidden(true)
                GSRow(title: "OpenAI compatible endpoint", text: "OpenRouter, vLLM, a company gateway or any server that speaks the same API.") {
                    statusView
                }
            }
            GSDivider()
            GSRow(title: "Quick setup", text: "Fills in the address and a small model. Paste your own key below.") {
                HStack(spacing: 10) {
                    ForEach(AIConnectFlow.endpointPresets) { preset in
                        Button(preset.title) { model.applyPreset(baseURL: preset.baseURL, model: preset.model) }
                            .buttonStyle(GSButtonStyle())
                            .accessibilityLabel("Fill in \(preset.title)")
                    }
                }
            }
            GSDivider()
            field("Base URL", "https://api.example.com/v1", Binding(get: { model.anyLLM.baseURL }, set: { model.anyLLM.baseURL = $0; model.endpointEdited() }))
            GSDivider()
            field("Model", "model name", Binding(get: { model.anyLLM.model }, set: { model.anyLLM.model = $0; model.endpointEdited() }))
            GSDivider()
            GSRow(title: "API key", text: model.anyLLMKeySaved ? "Saved in your Keychain. Zeus reads it once." : "Kept in your Keychain. Leave empty for a local server.") {
                HStack(spacing: 10) {
                    SecureField(model.anyLLMKeySaved ? "Saved" : "Paste a key", text: Binding(get: { model.keyDraft }, set: { model.keyDraft = $0 }))
                        .textFieldStyle(.plain)
                        .snapshotSafeText(model.keyDraft, placeholder: model.anyLLMKeySaved ? "Saved" : "Paste a key", secure: true)
                        .font(OB.font(13.5)).foregroundStyle(GS.text)
                        .padding(.horizontal, 10).frame(width: 220, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                        .accessibilityLabel("API key")
                        .onSubmit(save)
                    Button("Save key", action: save).buttonStyle(GSButtonStyle()).disabled(key.isEmpty)
                    if model.anyLLMKeySaved {
                        Button("Remove") { model.saveAnyLLMKey("") }.buttonStyle(GSButtonStyle())
                    }
                }
            }
            GSDivider()
            GSRow(title: "Test", text: testText) {
                HStack(spacing: 10) {
                    Button("Test") { Task { await model.testEndpoint() } }
                        .buttonStyle(GSButtonStyle(prominent: true)).disabled(!model.anyLLM.isComplete)
                }
            }
            if model.anyLLM.isInsecureRemote { GSInfo(text: "Plain http is only allowed for a server on this Mac. Use https.") }
        }
    }

    /// Return in an empty field must not remove the saved key (the Save button is disabled then too).
    private func save() {
        guard !model.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if model.saveAnyLLMKey(model.keyDraft) { model.keyDraft = "" }
    }

    @ViewBuilder private var statusView: some View {
        switch model.anyLLMTest {
        case .passed: GSStatus(ok: true, text: "Connected")
        case .testing: ProgressView().controlSize(.small)
        case .failed: GSStatus(ok: false, text: "Not connected")
        case .idle: EmptyView()
        }
    }

    private var testText: String {
        switch model.anyLLMTest {
        case .idle: "Lists the endpoint's models with a Haiku or mini size model set. It costs nothing."
        case .testing: "Reaching the endpoint."
        case .passed(let text), .failed(let text): text
        }
    }

    private func field(_ title: String, _ prompt: String, _ text: Binding<String>) -> some View {
        GSRow(title: title) {
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .snapshotSafeText(text.wrappedValue, placeholder: prompt)
                .font(OB.font(13.5)).foregroundStyle(GS.text)
                .padding(.horizontal, 10).frame(width: 320, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                .accessibilityLabel(title)
        }
    }
}
