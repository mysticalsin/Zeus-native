import SwiftUI
import ZeusCore

/// Settings card for adding a voice provider. The shell around this card is owned by the settings redesign.
struct VoiceProvidersCard: View {
    @State private var controller = VoiceProvidersController()

    var body: some View {
        VStack(alignment: .leading, spacing: VoiceProviderMetrics.standard.cardGap) {
            Text("Voice providers")
                .font(GS.cardTitle)
                .foregroundStyle(GS.text)
                .accessibilityAddTraits(.isHeader)
            Text(controller.model.onboarding)
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(controller.model.helper)
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(controller.model.maskingNote)
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(controller.model.rows) { row in
                providerRow(row)
            }
            if let id = controller.configuringID, id != VoiceProviderChoice.localID {
                keyRow(id)
                if let voices = controller.model.rows.first(where: { $0.id == id })?.voices, !voices.isEmpty {
                    voiceRow(id, voices)
                }
            }
            Text(controller.model.statusLine)
                .font(GS.rowText)
                .foregroundStyle(GS.text)
                .accessibilityLabel("Provider status")
                .accessibilityValue(controller.model.statusLine)
        }
        .padding(VoiceProviderMetrics.standard.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous)
                .fill(GS.card.opacity(0.92))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous))
        )
        .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.voiceProviders")
        .task { await controller.reload() }
    }

    private func providerRow(_ row: VoiceProviderRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(GS.rowTitle).foregroundStyle(GS.text)
                Text(row.isSelected ? "Selected" : "Available").font(GS.rowText).foregroundStyle(GS.secondary)
            }
            Spacer(minLength: 12)
            Text(row.status)
                .font(GS.rowText)
                .foregroundStyle(row.status == "Ready" ? GS.selectedText : GS.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(GS.window))
                .accessibilityLabel("\(row.title) status")
                .accessibilityValue(row.status)
            Button(row.isSelected ? "Selected" : "Use") { controller.use(row.id) }
                .buttonStyle(GSButtonStyle(prominent: row.isSelected))
                .disabled(row.id != VoiceProviderChoice.localID && !row.hasKey)
                .accessibilityLabel("Use \(row.title)")
            if row.id != VoiceProviderChoice.localID {
                Button("Key") { controller.configure(row.id) }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel("Add \(row.title)")
                if row.hasKey {
                    Button("Remove") { controller.remove(row.id) }
                        .buttonStyle(GSButtonStyle())
                        .accessibilityLabel("Remove \(row.title)")
                }
            }
        }
        .frame(minHeight: VoiceProviderMetrics.standard.rowHeight)
    }

    private func keyRow(_ id: String) -> some View {
        HStack(spacing: 10) {
            SecureField(controller.model.rows.first { $0.id == id }?.hasKey == true ? "Saved" : "Paste a key", text: $controller.keyDraft)
                .textFieldStyle(.plain)
                .snapshotSafeText(controller.keyDraft, placeholder: controller.model.rows.first { $0.id == id }?.hasKey == true ? "Saved" : "Paste a key", secure: true)
                .font(GS.rowText)
                .foregroundStyle(GS.text)
                .padding(.horizontal, 10)
                .frame(height: VoiceProviderMetrics.standard.rowHeight)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                .accessibilityLabel("API key")
            Button("Validate") { controller.validate() }
                .buttonStyle(GSButtonStyle(prominent: true))
                .disabled(controller.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.busy)
            Button("Test voice") { controller.testVoice() }
                .buttonStyle(GSButtonStyle())
                .disabled(controller.busy)
        }
        .frame(minHeight: VoiceProviderMetrics.standard.rowHeight)
    }

    private func voiceRow(_ id: String, _ voices: [ProviderVoice]) -> some View {
        HStack(spacing: 12) {
            Text("Voice").font(GS.rowTitle).foregroundStyle(GS.text)
            Spacer(minLength: 12)
            Picker("Voice", selection: Binding(
                get: { controller.model.rows.first { $0.id == id }?.selectedVoiceID ?? voices.first?.id ?? "" },
                set: { controller.chooseVoice($0) }
            )) {
                ForEach(voices) { voice in
                    Text(voice.name).tag(voice.id)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Voice")
        }
        .frame(minHeight: VoiceProviderMetrics.standard.rowHeight)
    }
}

@MainActor
@Observable
final class VoiceProvidersController {
    var model = VoiceProvidersCardModel(
        rows: [], keyIsMasked: true, onboarding: VoiceProviderCopy.onboarding, helper: VoiceProviderCopy.helper,
        maskingNote: VoiceProviderCopy.maskingNote, metrics: .standard, statusLine: "Speaking with the local voice."
    )
    var keyDraft = ""
    var configuringID: String?
    var busy = false
    private var session: VoiceProviderSession { PluginVoiceBridge.sharedSession() }

    func reload() async { model = await session.card() }

    func configure(_ id: String) {
        configuringID = id
        keyDraft = ""
    }

    func use(_ id: String) {
        if id == VoiceProviderChoice.localID { sessionSelect(.local) }
        else { sessionSelect(.provider(id)) }
    }

    func validate() {
        guard let id = configuringID else { return }
        let key = keyDraft
        keyDraft = ""
        busy = true
        Task {
            await session.saveKey(providerID: id, key: key)
            await session.select(.provider(id))
            model = await session.card()
            busy = false
        }
    }

    func chooseVoice(_ voiceID: String) {
        guard let id = configuringID else { return }
        Task {
            await session.select(.provider(id))
            await session.chooseVoice(providerID: id, voiceID: voiceID)
            model = await session.card()
        }
    }

    func remove(_ id: String) {
        Task {
            await session.remove(providerID: id)
            if configuringID == id { configuringID = nil }
            keyDraft = ""
            model = await session.card()
        }
    }

    func testVoice() {
        busy = true
        Task {
            let outcome = await session.speak(VoiceProviderCopy.sample)
            model = await session.card()
            if case .cloud = outcome.route, PluginAudioPlay.play(outcome.audio) {
                busy = false
                return
            }
            if case .cancelled = outcome.route {
                busy = false
                return
            }
            PluginAudioPlay.speakLocally(VoiceProviderCopy.sample)
            busy = false
        }
    }

    private func sessionSelect(_ choice: VoiceProviderChoice) {
        Task {
            await session.select(choice)
            model = await session.card()
        }
    }
}
