import SwiftUI
import ZeusCore

/// Settings > Voice: one voice section (QA19 simplicity), with takeover TTS provider chain inline.
struct ZeusVoiceCards: View {
    let navigation: GSNavigation
    private var voice: VoiceSettings { VoiceSettings.shared }
    private var settings: DictationSettings { DictationSettings.shared }
    private var designer: VoiceDesignModel { VoiceDesignModel.shared }
    private var testModel: VoiceTestModel { VoiceTestModel.shared }
    private var preview: VoicePreviewModel { VoicePreviewModel.shared }
    static let automaticTitle = "Automatic (best working voice)"
    /// Re-read every 30 seconds and on appear, so the OpenAI note and picker flip at the shutdown instant with the window open.
    @State private var now = Date()
    private var openAINote: String? { OpenAISpeechRetirement.settingsNote(model: voice.openAIModel, baseURL: voice.openAIBaseURL, at: now) }

    var body: some View {
        GSCard {
            GSRow(symbol: "key", title: "ElevenLabs key", text: voice.elevenKeySaved ? "Saved in Keychain. Zeus speaks with ElevenLabs first." : "Best Zeus voice. Create a key at elevenlabs.io, then paste it here. Stored only in your Keychain.") {
                HStack(spacing: 10) {
                    SecureField(voice.elevenKeySaved ? "Saved" : "Paste a key", text: Binding(get: { voice.elevenKeyDraft }, set: { voice.elevenKeyDraft = $0 }))
                        .textFieldStyle(.plain)
                        .snapshotSafeText(voice.elevenKeyDraft, placeholder: voice.elevenKeySaved ? "Saved" : "Paste a key", secure: true)
                        .font(OB.font(13.5)).foregroundStyle(GS.text)
                        .padding(.horizontal, 10).frame(width: 200, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                        .accessibilityLabel("ElevenLabs key")
                        .onSubmit { voice.saveElevenKey() }
                        .accessibilityIdentifier("settings.gsvoice-cards.elevenlabs-key")
                    Button("Save key") { voice.saveElevenKey() }.buttonStyle(GSButtonStyle()).disabled(voice.elevenKeyDraft.isEmpty)
                        .accessibilityIdentifier("settings.gsvoice-cards.save-key.3")
                    if !voice.elevenKeySaved {
                        Button("Get a key") { NSWorkspace.shared.open(URL(string: "https://elevenlabs.io")!) }.buttonStyle(GSButtonStyle())
                            .accessibilityIdentifier("settings.gsvoice-cards.get-a-key")
                    }
                    if voice.elevenKeySaved { Button("Remove") { voice.removeElevenKey() }.buttonStyle(GSButtonStyle())
                        .accessibilityIdentifier("settings.gsvoice-cards.remove") }
                }
            }
            if let line = voice.keyCheckMessage {
                GSInfo(text: line)
            }
            GSDivider()
            GSRow(symbol: "waveform", title: UltronVoicePlan.presetTitle, text: "The voice Zeus answers with unless you pick another below.")
            GSDivider()
            GSToggleRow(symbol: "speaker.wave.2.fill", title: "Speak replies", text: "Zeus reads its answers aloud instead of only showing them.", isOn: SettingsStore.shared.boolBinding("voice.speakReplies"))
            GSDivider()
            GSRow(symbol: "theatermasks", title: "Personality") {
                GSPopup(selection: Binding(get: { voice.personality.title }, set: { title in
                    if let choice = ZeusPersonality.allCases.first(where: { $0.title == title }) { voice.personality = choice }
                }), options: ZeusPersonality.allCases.map(\.title), label: "Personality")
            }
            GSDivider()
            GSRow(symbol: "circle.dashed", title: "Voice orb style") {
                GSPopup(selection: Binding(get: { VoiceOrbStyleStore.shared.style.title }, set: { title in
                    if let choice = VoiceOrbStyle.allCases.first(where: { $0.title == title }) { VoiceOrbStyleStore.shared.style = choice }
                }), options: VoiceOrbStyle.allCases.map(\.title), label: "Voice orb style")
            }
            GSDivider()
            GSToggleRow(symbol: "waveform.badge.plus", title: "Ultron effect", text: "Adds a layered, robotic edge to the spoken voice.",
                        isOn: Binding(get: { UltronVoiceEffect.enabled }, set: { UltronVoiceEffect.enabled = $0 }))
            GSDivider()
            GSRow(symbol: "slider.horizontal.3", title: "Effect intensity", text: String(format: "%.0f%%", UltronVoiceEffect.intensity * 100)) {
                Slider(value: Binding(get: { Double(UltronVoiceEffect.intensity) }, set: { UltronVoiceEffect.intensity = Float($0) }),
                       in: 0...1, step: 0.05)
                    .frame(width: 160)
                    .accessibilityLabel("Effect intensity")
                    .accessibilityValue(String(format: "%.0f percent", UltronVoiceEffect.intensity * 100))
                    .accessibilityIdentifier("settings.gsvoice-cards.effect-intensity")
            }
            GSDivider()
            GSRow(symbol: "waveform.path", title: "Speaks with") {
                GSPopup(selection: Binding(get: { voice.engineAuto ? Self.automaticTitle : voice.ttsProvider.title }, set: { title in
                    if title == Self.automaticTitle { voice.engineAuto = true }
                    else if let p = VoiceTTSProvider.allCases.first(where: { $0.title == title }) { voice.ttsProvider = p }
                }), options: [Self.automaticTitle] + VoiceTTSProvider.allCases.map(\.title), label: "Speaks with")
            }
            if let line = OpenAISpeechRetirement.endedChoiceLine(choice: voice.engineChoice, retired: voice.openAIRetired(now: now),
                                                                 effective: voice.routeDecisions().first?.engine.label ?? UltronEngine.system.label) {
                GSInfo(text: line)
            }
            GSDivider()
            GSRow(symbol: "sparkles", title: "Voice quality", text: voice.elevenQuality.detail) {
                GSPopup(selection: Binding(get: { voice.elevenQuality.title }, set: { title in
                    if let choice = ElevenLabsQuality.allCases.first(where: { $0.title == title }) { voice.elevenQuality = choice }
                }), options: ElevenLabsQuality.allCases.map(\.title), label: "Voice quality")
            }
            if !voice.macVoiceHintDismissed, Self.macVoiceHintNeeded {
                GSDivider()
                GSRow(symbol: "person.badge.plus", title: "A better Mac voice",
                      text: "Only the basic Mac voices are installed. Without a cloud key Zeus sounds best with an Enhanced or Premium voice. Nothing is downloaded until you choose one.") {
                    HStack(spacing: 10) {
                        Button("Open Spoken Content") { Self.openSpokenContent(); voice.macVoiceHintDismissed = true }
                            .buttonStyle(GSButtonStyle(prominent: true))
                            .accessibilityIdentifier("settings.gsvoice-cards.open-spoken-content")
                        Button("Dismiss") { voice.macVoiceHintDismissed = true }.buttonStyle(GSButtonStyle())
                            .accessibilityIdentifier("settings.gsvoice-cards.dismiss")
                    }
                }
            }
            GSDivider()
            GSRow(symbol: "waveform.badge.mic", title: "Test voice", text: "Speaks a short line in English and in French and times the first sound.") {
                Button(testModel.running ? "Speaking" : "Test voice") { testModel.run(speaker: Self.previewSpeaker) }
                    .buttonStyle(GSButtonStyle(prominent: true)).disabled(testModel.running)
                    .accessibilityLabel(testModel.running ? "Speaking" : "Test voice")
                    .accessibilityIdentifier("settings.gsvoice-cards.speaking")
            }
            ForEach(testModel.rows) { row in
                GSInfo(text: row.summary)
            }
            GSDivider()
            GSRow(symbol: "waveform.badge.mic", title: "Answer voice") {
                Button(voice.testing ? "Playing" : "Preview") { voice.test(with: Self.previewSpeaker) }
                    .buttonStyle(GSButtonStyle(prominent: true)).disabled(voice.testing)
                    .accessibilityLabel(voice.testing ? "Playing" : "Preview")
                    .accessibilityIdentifier("settings.gsvoice-cards.playing")
            }
            if let line = voice.previewMessage {
                GSDivider()
                GSInfo(text: line)
            }
            if let line = voice.lastProviderFallbackMessage {
                GSDivider()
                GSInfo(text: line)
            } else if isElevenLabsPaused {
                GSDivider()
                GSInfo(text: "ElevenLabs is paused for a few minutes. Using the next voice.")
            }
            if let line = voice.keyMessage {
                GSDivider()
                GSInfo(text: line)
            }
            GSDivider()
            GSRow(symbol: "key", title: "OpenAI TTS key", text: openAINote ?? (voice.openAIKeySaved ? "Saved in Keychain." : "Backup voice. Create a key at platform.openai.com, then paste it here. Stored only in your Keychain.")) {
                HStack(spacing: 10) {
                    SecureField(voice.openAIKeySaved ? "Saved" : "Paste a key", text: Binding(get: { voice.openAIKeyDraft }, set: { voice.openAIKeyDraft = $0 }))
                        .textFieldStyle(.plain)
                        .snapshotSafeText(voice.openAIKeyDraft, placeholder: voice.openAIKeySaved ? "Saved" : "Paste a key", secure: true)
                        .font(OB.font(13.5)).foregroundStyle(GS.text)
                        .padding(.horizontal, 10).frame(width: 200, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                        .accessibilityLabel("OpenAI TTS key")
                        .onSubmit { voice.saveOpenAIKey() }
                        .accessibilityIdentifier("settings.gsvoice-cards.openai-tts-key")
                    Button("Save key") { voice.saveOpenAIKey() }.buttonStyle(GSButtonStyle()).disabled(voice.openAIKeyDraft.isEmpty)
                        .accessibilityIdentifier("settings.gsvoice-cards.save-key.2")
                    if voice.openAIKeySaved { Button("Clear") { voice.removeOpenAIKey() }.buttonStyle(GSButtonStyle())
                        .accessibilityIdentifier("settings.gsvoice-cards.clear.2") }
                }
            }
            if voice.openAIKeySaved {
                GSDivider()
                GSRow(symbol: "person.wave.2", title: "OpenAI voice",
                      text: openAINote
                          ?? "Used when OpenAI speaks. Marin and Cedar need the gpt-4o-mini-tts model.") {
                    if voice.openAIRetired(now: now) {
                        Text(OpenAISpeechRetirement.endedNote).font(OB.font(13.5)).foregroundStyle(GS.text.opacity(0.5))
                            .accessibilityLabel("OpenAI voice, ended")
                    } else {
                        voicePicker(provider: .openAICompatible, voices: OpenAIVoiceCatalog.voices(forModel: voice.openAIModel, baseURL: voice.openAIBaseURL, at: now),
                                    selected: voice.openAIVoice, label: "OpenAI voice") { voice.openAIVoice = $0 }
                    }
                }
            }
            GSDivider()
            GSRow(symbol: "key", title: "Gemini TTS key", text: voice.geminiKeySaved ? "Saved in Keychain." : "Optional Google voice. Create a key in Google AI Studio, then paste it here. Stored only in your Keychain.") {
                HStack(spacing: 10) {
                    SecureField(voice.geminiKeySaved ? "Saved" : "Paste a key", text: Binding(get: { voice.geminiKeyDraft }, set: { voice.geminiKeyDraft = $0 }))
                        .textFieldStyle(.plain)
                        .snapshotSafeText(voice.geminiKeyDraft, placeholder: voice.geminiKeySaved ? "Saved" : "Paste a key", secure: true)
                        .font(OB.font(13.5)).foregroundStyle(GS.text)
                        .padding(.horizontal, 10).frame(width: 200, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                        .accessibilityLabel("Gemini TTS key")
                        .onSubmit { voice.saveGeminiKey() }
                        .accessibilityIdentifier("settings.gsvoice-cards.gemini-tts-key")
                    Button("Save key") { voice.saveGeminiKey() }.buttonStyle(GSButtonStyle()).disabled(voice.geminiKeyDraft.isEmpty)
                        .accessibilityIdentifier("settings.gsvoice-cards.save-key")
                    if voice.geminiKeySaved { Button("Clear") { voice.removeGeminiKey() }.buttonStyle(GSButtonStyle())
                        .accessibilityIdentifier("settings.gsvoice-cards.clear") }
                }
            }
            if voice.geminiKeySaved {
                GSDivider()
                GSRow(symbol: "person.wave.2", title: "Gemini voice", text: "Thirty Google voices. Preview speaks one short sentence with your key.") {
                    voicePicker(provider: .gemini, voices: GeminiVoiceCatalog.voices,
                                selected: voice.geminiVoice, label: "Gemini voice") { voice.geminiVoice = $0 }
                }
            }
            if let line = preview.message {
                GSInfo(text: line)
            }
            if voice.elevenKeySaved {
                GSDivider()
                GSRow(symbol: "person.wave.2", title: "ElevenLabs voice") {
                    if voice.loadingLibrary {
                        ProgressView().controlSize(.small)
                    } else if voice.library.isEmpty {
                        Button("Load voices") { Task { await voice.loadLibrary() } }.buttonStyle(GSButtonStyle())
                            .accessibilityIdentifier("settings.gsvoice-cards.load-voices")
                    } else {
                        GSPopup(selection: Binding(get: { voice.library.first { $0.id == voice.elevenVoiceID }?.name ?? voice.elevenVoiceID },
                                                   set: { name in if let item = voice.library.first(where: { $0.name == name }) { voice.setElevenVoice(item.id) } }),
                                options: voice.library.map(\.name), label: "ElevenLabs voice")
                    }
                }
                if let line = voice.libraryMessage {
                    GSInfo(text: line)
                }
            }
            if let line = voice.elevenLabsStatusMessage {
                GSInfo(text: line)
            }
            if voice.ttsProvider == .kokoro || voice.kokoroReady || voice.settingUpKokoro {
                GSDivider()
                GSRow(symbol: "waveform.circle", title: "Kokoro on this Mac", text: kokoroText) {
                    if voice.settingUpKokoro { ProgressView().controlSize(.small) }
                    else if voice.kokoroReady { GSStatus(ok: true, text: "Ready") }
                    else { Button("Set up Kokoro") { voice.setUpKokoro() }.buttonStyle(GSButtonStyle(prominent: true))
                        .accessibilityIdentifier("settings.gsvoice-cards.set-up-kokoro") }
                }
                if voice.kokoroReady {
                    GSDivider()
                    GSRow(symbol: "person.crop.circle", title: "Kokoro voice") {
                        GSPopup(selection: Binding(get: {
                            let id = voice.kokoroVoice
                            let long = VoiceSettings.kokoroVoices.first { $0.id == id }?.name ?? id
                            return KokoroVoiceLabels.pickerTitle(voiceID: id, longName: long)
                        }, set: { title in
                            if let item = VoiceSettings.kokoroVoices.first(where: {
                                KokoroVoiceLabels.pickerTitle(voiceID: $0.id, longName: $0.name) == title
                            }) { voice.kokoroVoice = item.id }
                        }), options: VoiceSettings.kokoroVoices.map { KokoroVoiceLabels.pickerTitle(voiceID: $0.id, longName: $0.name) },
                                label: "Kokoro voice")
                    }
                    GSDivider()
                    GSRow(symbol: "speedometer", title: "Pace", text: String(format: "%.2fx", voice.kokoroSpeed)) {
                        Slider(value: Binding(get: { voice.kokoroSpeed }, set: { voice.kokoroSpeed = $0 }), in: 0.7...1.3, step: 0.05)
                            .snapshotSafeSlider(value: voice.kokoroSpeed, in: 0.7...1.3)
                            .frame(width: 160)
                            .accessibilityLabel("Kokoro pace")
                            .accessibilityValue(String(format: "%.2f times", voice.kokoroSpeed))
                            .accessibilityIdentifier("settings.gsvoice-cards.kokoro-pace")
                    }
                }
            }
            designRows
        }
        .onAppear { now = Date() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        GSCard("Speech to text") {
            GSRow(symbol: "waveform.and.mic", title: "Hears you with", text: settings.engine.detail) {
                GSPopup(selection: Binding(get: { SpeechEngineBoard.shared.pickerTitle(settings.engine) },
                                           set: { title in SpeechEngineBoard.shared.choose(pickerTitle: title) }),
                        options: TranscriptionEngineKind.allCases.map { SpeechEngineBoard.shared.pickerTitle($0) }, label: "Speech to text engine")
            }
            GSDivider()
            GSLinkRow(symbol: "waveform", title: "Use for voice commands too", destination: .dictation, navigation: navigation)
            if let message = SpeechEngineBoard.shared.message { GSInfo(text: message) }
        }
        .task { await SpeechEngineBoard.shared.refresh() }
    }

    @ViewBuilder private var designRows: some View {
        if voice.elevenKeySaved {
            GSDivider()
            GSRow(symbol: "wand.and.stars", title: voice.hasDesignedVoice ? "Design a new Zeus voice" : "Create Zeus voice", text: designer.status) {
                if designer.busy { ProgressView().controlSize(.small) }
                else {
                    Button(designer.previews.isEmpty ? (voice.hasDesignedVoice ? "Design" : "Create Zeus voice") : "Again") { designer.design() }
                        .buttonStyle(GSButtonStyle(prominent: designer.previews.isEmpty))
                        .accessibilityLabel(designer.previews.isEmpty ? (voice.hasDesignedVoice ? "Design" : "Create Zeus voice") : "Again")
                        .accessibilityIdentifier("settings.gsvoice-cards.design")
                }
            }
            ForEach(Array(designer.previews.enumerated()), id: \.element.id) { index, preview in
                GSDivider()
                GSRow(symbol: "waveform", title: "Voice \(index + 1)") {
                    HStack(spacing: 10) {
                        Button(designer.playingID == preview.id ? "Stop" : "Play") { designer.togglePlay(preview) }
                            .buttonStyle(GSButtonStyle())
                            .accessibilityLabel(designer.playingID == preview.id ? "Stop" : "Play")
                            .accessibilityIdentifier("settings.gsvoice-cards.stop")
                        Button("Use") { designer.use(preview) }
                            .buttonStyle(GSButtonStyle(prominent: true)).disabled(designer.busy)
                            .accessibilityIdentifier("settings.gsvoice-cards.use")
                    }
                }
            }
        }
    }

    /// System Settings > Accessibility > Spoken Content. The pane anchor is not documented by Apple, so the
    /// Accessibility pane opens if the anchor is refused.
    /// Looked up once: enumerating the installed voices is not free and the view body runs often.
    @MainActor static let macVoiceHintNeeded = Speaker.needsBetterMacVoice(languageCode: Locale.current.identifier)

    @MainActor static func openSpokenContent() {
        let anchored = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent")!
        if !NSWorkspace.shared.open(anchored) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!)
        }
    }

    @MainActor static let previewSpeaker = Speaker(languageCode: Locale.current.identifier)

    private var isElevenLabsPaused: Bool {
        guard let until = voice.elevenLabsPausedUntil else { return false }
        return until > Date()
    }

    private var effectiveEngineDescription: String {
        let chain = VoiceTTSChain.providers(
            chosen: voice.ttsProvider,
            availability: voice.ttsAvailability(elevenLabsPaused: isElevenLabsPaused),
            isPaused: { voice.isProviderPaused($0) }
        )
        guard let first = chain.first else {
            return voice.kokoroReady ? "Kokoro \(voice.kokoroVoice)" : "Mac voice"
        }
        switch first {
        case .kokoro: return "Kokoro \(voice.kokoroVoice)"
        case .chatterbox: return "Local Chatterbox Turbo"
        case .elevenLabs:
            if isElevenLabsPaused, voice.kokoroReady {
                return "Kokoro \(ElevenLabsVoice.offlineKokoroVoice) (ElevenLabs key rejected)"
            }
            return "ElevenLabs"
        case .openAICompatible: return "OpenAI-compatible TTS"
        case .gemini: return "Google Gemini TTS"
        }
    }

    /// A voice popup with a Preview button. Rows read "Name, tone"; the id is what gets saved.
    private func voicePicker(provider: VoiceTTSProvider, voices: [CatalogVoice], selected: String, label: String,
                             choose: @escaping (String) -> Void) -> some View {
        func rowTitle(_ item: CatalogVoice) -> String { "\(item.title), \(item.detail)" }
        return HStack(spacing: 10) {
            GSPopup(selection: Binding(get: { voices.first { $0.id == selected }.map(rowTitle) ?? selected },
                                       set: { title in if let item = voices.first(where: { rowTitle($0) == title }) { choose(item.id) } }),
                    options: voices.map(rowTitle), label: label)
            Button(preview.isActive(provider, selected) ? (preview.loading ? "Loading" : "Stop") : "Preview") {
                preview.toggle(provider, voice: selected)
            }
            .buttonStyle(GSButtonStyle()).accessibilityLabel("\(label) preview")
            .accessibilityIdentifier("settings.gsvoice-cards.preview")
        }
    }

    private var kokoroText: String {
        if let message = voice.kokoroMessage { return message }
        if voice.kokoroReady { return "Runs on this Mac. Nothing is sent anywhere." }
        return LocalPython.systemPython == nil ? "Needs Python 3 on this Mac." : "Sets up the voice on this Mac and downloads it once."
    }
}
