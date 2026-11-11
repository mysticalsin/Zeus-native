import SwiftUI
import ZeusCore

/// Settings > Voice: one voice section (QA19 simplicity), with takeover TTS provider chain inline.
struct ZeusVoiceCards: View {
    private var voice: VoiceSettings { VoiceSettings.shared }
    private var settings: DictationSettings { DictationSettings.shared }
    private var designer: VoiceDesignModel { VoiceDesignModel.shared }

    var body: some View {
        GSCard {
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
            }
            GSDivider()
            GSRow(symbol: "waveform.path", title: "Speaks with") {
                GSPopup(selection: Binding(get: { voice.ttsProvider.title }, set: { title in
                    if let p = VoiceTTSProvider.allCases.first(where: { $0.title == title }) { voice.ttsProvider = p }
                }), options: VoiceTTSProvider.allCases.map(\.title), label: "Speaks with")
            }
            GSDivider()
            GSRow(symbol: "waveform.badge.mic", title: "Answer voice") {
                Button(voice.testing ? "Playing" : "Preview") { voice.test(with: Self.previewSpeaker) }
                    .buttonStyle(GSButtonStyle(prominent: true)).disabled(voice.testing)
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
            if voice.ttsProvider == .openAICompatible || voice.openAIKeySaved {
                GSDivider()
                GSRow(symbol: "key", title: "OpenAI TTS key", text: voice.openAIKeySaved ? "Saved in Keychain." : "Saved in Keychain when you add one.") {
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
                        Button("Save key") { voice.saveOpenAIKey() }.buttonStyle(GSButtonStyle()).disabled(voice.openAIKeyDraft.isEmpty)
                        if voice.openAIKeySaved { Button("Clear") { voice.removeOpenAIKey() }.buttonStyle(GSButtonStyle()) }
                    }
                }
            }
            if voice.ttsProvider == .elevenLabs || voice.elevenKeySaved {
                GSDivider()
                GSRow(symbol: "key", title: "ElevenLabs key", text: voice.elevenKeySaved ? "Saved in Keychain." : "Saved in Keychain when you add one.") {
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
                        Button("Save key") { voice.saveElevenKey() }.buttonStyle(GSButtonStyle()).disabled(voice.elevenKeyDraft.isEmpty)
                        if voice.elevenKeySaved { Button("Remove") { voice.removeElevenKey() }.buttonStyle(GSButtonStyle()) }
                    }
                }
                if voice.elevenKeySaved {
                    GSDivider()
                    GSRow(symbol: "person.wave.2", title: "ElevenLabs voice") {
                        if voice.loadingLibrary {
                            ProgressView().controlSize(.small)
                        } else if voice.library.isEmpty {
                            Button("Load voices") { Task { await voice.loadLibrary() } }.buttonStyle(GSButtonStyle())
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
            }
            if voice.ttsProvider == .kokoro || voice.kokoroReady || voice.settingUpKokoro {
                GSDivider()
                GSRow(symbol: "waveform.circle", title: "Kokoro on this Mac", text: kokoroText) {
                    if voice.settingUpKokoro { ProgressView().controlSize(.small) }
                    else if voice.kokoroReady { GSStatus(ok: true, text: "Ready") }
                    else { Button("Set up Kokoro") { voice.setUpKokoro() }.buttonStyle(GSButtonStyle(prominent: true)) }
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
                    }
                }
            }
            designRows
        }
        GSCard("Speech to text") {
            GSRow(symbol: "waveform.and.mic", title: "Hears you with", text: settings.engine.detail) {
                GSPopup(selection: Binding(get: { SpeechEngineBoard.shared.pickerTitle(settings.engine) },
                                           set: { title in SpeechEngineBoard.shared.choose(pickerTitle: title) }),
                        options: TranscriptionEngineKind.allCases.map { SpeechEngineBoard.shared.pickerTitle($0) }, label: "Speech to text engine")
            }
            GSDivider()
            GSToggleRow(symbol: "waveform", title: "Use for voice commands too",
                        isOn: Binding(get: { settings.engineForVoice }, set: { settings.engineForVoice = $0 }))
            if let message = SpeechEngineBoard.shared.message { GSInfo(text: message) }
        }
        .task { await SpeechEngineBoard.shared.refresh() }
    }

    @ViewBuilder private var designRows: some View {
        if voice.elevenKeySaved {
            GSDivider()
            GSRow(symbol: "wand.and.stars", title: "Design a voice", text: designer.status) {
                if designer.busy { ProgressView().controlSize(.small) }
                else {
                    Button(designer.previews.isEmpty ? "Design" : "Again") { designer.design() }
                        .buttonStyle(GSButtonStyle(prominent: designer.previews.isEmpty))
                }
            }
            ForEach(Array(designer.previews.enumerated()), id: \.element.id) { index, preview in
                GSDivider()
                GSRow(symbol: "waveform", title: "Voice \(index + 1)") {
                    HStack(spacing: 10) {
                        Button(designer.playingID == preview.id ? "Stop" : "Play") { designer.togglePlay(preview) }
                            .buttonStyle(GSButtonStyle())
                        Button("Use") { designer.use(preview) }
                            .buttonStyle(GSButtonStyle(prominent: true)).disabled(designer.busy)
                    }
                }
            }
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
        }
    }

    private var kokoroText: String {
        if let message = voice.kokoroMessage { return message }
        if voice.kokoroReady { return "Runs on this Mac. Nothing is sent anywhere." }
        return LocalPython.systemPython == nil ? "Needs Python 3 on this Mac." : "Sets up a private Python environment and downloads the voice once."
    }
}
