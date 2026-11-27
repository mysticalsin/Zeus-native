import SwiftUI
import ZeusCore

/// The voice choice inside Settings. Native controls, glass material, no extra window.
struct VoiceProvidersCard: View {
    var embedded = false
    var body: some View { VoiceProviderPicker(embedded: embedded) }
}

/// Pick a provider, paste a key, validate, then Test. Three interactions when the first voice is kept.
struct VoiceProviderPicker: View {
    var embedded = false
    var compact = false
    @State private var controller = VoiceProvidersController()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let selected = controller.configuringID
            ?? controller.model.rows.first { $0.isSelected }?.id
            ?? VoiceProviderChoice.localID
        VStack(alignment: .leading, spacing: compact ? 12 : VoiceProviderMetrics.standard.cardGap) {
            if !compact {
                Text("Voice providers")
                    .font(GS.cardTitle)
                    .foregroundStyle(GS.text)
                    .accessibilityAddTraits(.isHeader)
                Text(controller.model.helper)
                    .font(GS.rowText)
                    .foregroundStyle(GS.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Text("Provider").font(GS.rowTitle).foregroundStyle(GS.text)
                Spacer(minLength: 12)
                Picker("Provider", selection: Binding(
                    get: { selected },
                    set: { controller.use($0) }
                )) {
                    Text("Local voice").tag(VoiceProviderChoice.localID)
                    ForEach(controller.model.rows.filter { $0.id != VoiceProviderChoice.localID }) { row in
                        Text(row.title).tag(row.id)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("settings.voiceProviders.provider")
                .accessibilityLabel("Provider")
            }
            .frame(minHeight: VoiceProviderMetrics.standard.rowHeight)
            if selected != VoiceProviderChoice.localID {
                Toggle("Use for replies", isOn: Binding(
                    get: { controller.model.rows.first { $0.id == selected }?.isSelected ?? false },
                    set: { controller.use($0 ? selected : VoiceProviderChoice.localID) }
                ))
                .toggleStyle(.switch)
                .font(GS.rowText)
                .foregroundStyle(GS.text)
                .accessibilityIdentifier("settings.voiceProviders.enabled")
                keyRow(selected)
                if let voices = controller.model.rows.first(where: { $0.id == selected })?.voices, !voices.isEmpty {
                    voiceRow(selected, voices)
                }
            }
            HStack(spacing: 8) {
                if controller.busy { ProgressView().controlSize(.small) }
                Text(controller.model.statusLine)
                    .font(GS.rowText)
                    .foregroundStyle(GS.text)
                    .accessibilityIdentifier("settings.voiceProviders.status")
                    .accessibilityLabel("Provider status")
                    .accessibilityValue(controller.model.statusLine)
            }
        }
        .padding(embedded ? 0 : VoiceProviderMetrics.standard.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { if !embedded { glass } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.voiceProviders")
        .task { await controller.reload() }
    }

    /// Same material as the glass settings shell: translucency, solid when Reduce Transparency is on.
    private var glass: some View {
        let solid = reduceTransparency || TopBarStyle.isSnapshot
        return RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous)
            .fill(solid ? AnyShapeStyle(GS.window) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(
                RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(solid ? 0 : 0.18), lineWidth: 1)
            )
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
                .accessibilityIdentifier("settings.voiceProviders.key")
                .accessibilityLabel("API key")
            Button("Validate") { controller.validate() }
                .buttonStyle(GSButtonStyle(prominent: true))
                .disabled(controller.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.busy)
                .accessibilityIdentifier("settings.voiceProviders.validate")
            Button("Test voice") { controller.testVoice() }
                .buttonStyle(GSButtonStyle())
                .disabled(controller.busy)
                .accessibilityIdentifier("settings.voiceProviders.test")
            if controller.model.rows.first(where: { $0.id == id })?.hasKey == true {
                Button("Remove") { controller.remove(id) }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityIdentifier("settings.voiceProviders.remove.\(id)")
                    .accessibilityLabel("Remove \(controller.model.rows.first { $0.id == id }?.title ?? "provider")")
            }
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
            .accessibilityIdentifier("settings.voiceProviders.voice")
            .accessibilityLabel("Voice")
        }
        .frame(minHeight: VoiceProviderMetrics.standard.rowHeight)
    }
}

/// Compact provider switch for a later companion or persona surface. It does not open a window.
struct VoiceProviderQuickSwitch: View {
    var body: some View { VoiceProviderPicker(embedded: true, compact: true) }
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
        configuringID = id == VoiceProviderChoice.localID ? nil : id
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
            let played = await PluginAudioPlay.play(outcome.audio)
            if case .cloud = outcome.route, played {
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
