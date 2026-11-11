import SwiftUI
import ZeusCore

/// The Engine picker: every speech-to-text engine, grouped "On this Mac" and "Cloud", each with
/// its status and one click to Download, Add key or Use. Shown on the Murmure and Dictation pages.
struct SpeechEngineCard: View {
    var title = "Engine"
    /// The Dictation page also offers the whisper.cpp model size.
    var showsWhisperModel = false
    /// Murmure settings: one row plus picker, not the full engine catalog.
    var compact = false
    /// Murmure only links to the Dictation page, where "Use for voice commands too" lives.
    var navigation: GSNavigation? = nil
    private var board: SpeechEngineBoard { SpeechEngineBoard.shared }
    private var settings: DictationSettings { DictationSettings.shared }

    var body: some View {
        GSCard(title) {
            if compact {
                compactBody
            } else {
                fullBody
            }
            GSDivider()
            if compact, let navigation {
                GSLinkRow(symbol: "waveform", title: "Use for voice commands too", destination: .dictation, navigation: navigation)
            } else {
                GSToggleRow(symbol: "waveform", title: "Use for voice commands too",
                            text: "Spoken commands to Zeus use this engine instead of Apple's.",
                            isOn: Binding(get: { settings.engineForVoice }, set: { settings.engineForVoice = $0 }))
            }
            if let message = board.message { GSInfo(text: message) }
        }
        .task { await board.refresh() }
    }

    @ViewBuilder private var compactBody: some View {
        GSRow(symbol: symbol(settings.engine), title: settings.engine.title, text: "") {
            GSPopup(selection: Binding(get: { board.pickerTitle(settings.engine) },
                                       set: { title in board.choose(pickerTitle: title) }),
                    options: TranscriptionEngineKind.allCases.map { board.pickerTitle($0) }, label: "\(title) engine")
        }
    }

    @ViewBuilder private var fullBody: some View {
        ForEach(TranscriptionEngineKind.Group.allCases, id: \.self) { group in
            Text(group.rawValue).font(OB.font(12.5, .semibold)).foregroundStyle(GS.secondary)
                .padding(.top, 14).padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(TranscriptionEngineKind.engines(in: group).enumerated()), id: \.element) { index, kind in
                if index > 0 { GSDivider() }
                row(kind)
                if kind == .whisper, showsWhisperModel, WhisperCppEngine.binary != nil { whisperModelRow }
                if board.editingKey == kind { keyEditor(kind) }
            }
        }
    }

    private func row(_ kind: TranscriptionEngineKind) -> some View {
        let availability = board.availability(kind)
        let megabytes = kind == .whisper ? WhisperCppEngine.selectedModel.megabytes : nil
        let line = EngineStatusMapping.line(for: kind, availability: availability, selected: settings.engine == kind, megabytes: megabytes, cancellable: kind == .whisperKit)
        let text = line.reason ?? ""
        return GSRow(symbol: symbol(kind), title: kind.title, text: text) {
            HStack(spacing: 10) {
                if line.action == .inUse {
                    GSStatus(ok: true, text: "In use")
                } else {
                    GSStatus(ok: line.ok, text: line.label)
                }
                if let actionTitle = line.actionTitle {
                    Button(actionTitle) { board.perform(line.action, for: kind) }
                        .buttonStyle(GSButtonStyle(prominent: line.action != .use))
                        .accessibilityLabel("\(actionTitle) \(kind.title)")
                }
            }
        }
    }

    private func symbol(_ kind: TranscriptionEngineKind) -> String {
        switch kind {
        case .apple, .appleAnalyzer: "applelogo"
        case .elevenLabs, .openAI: "cloud"
        default: "waveform.and.mic"
        }
    }

    private var whisperModelRow: some View {
        GSRow(title: "Whisper model", text: WhisperCppEngine.isDownloaded(WhisperCppEngine.selectedModel) ? "On this Mac." : "Not downloaded yet.") {
            GSPopup(selection: Binding(get: { WhisperCppEngine.selectedModel.title },
                                       set: { title in
                                           if let model = WhisperCppEngine.models.first(where: { $0.title == title }) {
                                               WhisperCppEngine.selectedModelID = model.id
                                               board.message = nil
                                               Task { await board.refresh() }
                                           }
                                       }),
                    options: WhisperCppEngine.models.map(\.title), label: "Whisper model")
        }
    }

    private func keyEditor(_ kind: TranscriptionEngineKind) -> some View {
        HStack(spacing: 10) {
            SecureField(kind == .openAI ? "sk-\u{2026}" : "Paste your ElevenLabs key", text: Binding(get: { board.keyDraft }, set: { board.keyDraft = $0 }))
                .textFieldStyle(.plain)
                .snapshotSafeText(board.keyDraft, placeholder: kind == .openAI ? "sk-\u{2026}" : "Paste your ElevenLabs key", secure: true)
                .font(OB.font(13.5)).foregroundStyle(GS.text)
                .padding(.horizontal, 10).frame(width: 260, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                .accessibilityLabel("\(kind.title) API key")
                .onSubmit { board.saveKey() }
            Button("Save key") { board.saveKey() }.buttonStyle(GSButtonStyle(prominent: true)).disabled(board.keyDraft.isEmpty)
            Button("Cancel") { board.editingKey = nil; board.keyDraft = "" }.buttonStyle(GSButtonStyle())
        }
        .padding(.bottom, 14)
    }
}

private struct RecommendedPill: View {
    var body: some View {
        Text("Recommended")
            .font(OB.font(12, .semibold)).foregroundStyle(OB.allowed)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().strokeBorder(OB.allowed, lineWidth: 1))
            .accessibilityLabel("Recommended")
    }
}
