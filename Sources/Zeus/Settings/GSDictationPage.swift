import AppKit
import Observation
import SwiftUI
import ZeusCore

/// Draft text for the Dictation page (this toolchain has no SwiftUI `@State` macro).
@MainActor
@Observable
final class DictationPageState {
    static let shared = DictationPageState()
    var editingKey: String?
    /// A new mode being written. It is only saved by "Save mode", so Cancel leaves nothing behind.
    var draftMode: DictationMode?
    var name = ""
    var prompt = ""
    var wordsText = ""
    var replacementsText = ""
    var loaded = false
    /// What the two boxes were last filled from, so Save keeps words learned elsewhere since.
    var loadedVocabulary = Vocabulary()

    func loadVocabulary(_ vocabulary: Vocabulary) {
        loadedVocabulary = vocabulary
        wordsText = vocabulary.words.joined(separator: ", ")
        replacementsText = vocabulary.replacements.map { "\($0.original) -> \($0.with)" }.joined(separator: "\n")
        loaded = true
    }

    func vocabulary(keeping existing: Vocabulary) -> Vocabulary {
        let words = wordsText.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let replacements = replacementsText.split(separator: "\n").compactMap { line -> Replacement? in
            let parts = line.components(separatedBy: "->")
            guard parts.count == 2 else { return nil }
            let original = parts[0].trimmingCharacters(in: .whitespaces), with = parts[1].trimmingCharacters(in: .whitespaces)
            guard !original.isEmpty else { return nil }
            return Replacement(id: existing.replacements.first { $0.original == original }?.id ?? UUID(), original: original, with: with)
        }
        return Vocabulary(words: words, replacements: replacements)
    }
}

/// Settings > Dictation: the dictation tools on top of the same pipeline Murmure uses.
/// Modes, the recorder pill, the speech engine (the same picker as Settings › Murmure),
/// custom vocabulary and history.
struct DictationSettingsPage: View {
    let context: GSContext
    let navigation: GSNavigation
    private var settings: DictationSettings { DictationSettings.shared }
    private var page: DictationPageState { DictationPageState.shared }
    private var controller: DictationController? { DictationHub.shared.controller }
    private var topBar: TopBarModel? { controller?.topBarModel }
    private var tester: MicrophoneTester { MicrophoneTester.shared }

    var body: some View {
        GSPageHeading(section: .dictation, subtitle: "Speak anywhere. Choose how it is written.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Recording") {
            GSToggleRow(symbol: "mic", title: "Dictation", text: "Hold the key to speak. Release to write it where your cursor is.",
                        isOn: Binding(get: { settings.enabled }, set: { settings.enabled = $0 }))
            GSDivider()
            ShortcutLinkRow(symbol: "keyboard", title: "Dictation shortcut", current: settings.key, navigation: navigation)
            GSDivider()
            KeyAccessLinkRow(navigation: navigation)
            GSDivider()
            let behaviors = settings.availableBehaviors
            GSRow(symbol: "hand.tap", title: "Shortcut behavior",
                  text: settings.key == Preferences.shared.pushToTalk
                    ? "The talk key is shared, so it keeps hold-to-dictate and double-tap-to-talk. Choose a separate key to enable press-to-toggle."
                    : settings.selectedBehavior.detail) {
                GSPopup(selection: Binding(get: { settings.selectedBehavior.title },
                                           set: { title in settings.behavior = behaviors.first { $0.title == title } ?? .holdToSpeak }),
                        options: behaviors.map(\.title), label: "Shortcut behavior")
            }
            GSDivider()
            GSRow(symbol: "globe", title: "Dictation language", text: "") {
                GSPopup(selection: Binding(get: { settings.language.title },
                                           set: { value in settings.language = DictationLanguage(persistedValue: value) }),
                        options: DictationLanguage.allCases.map(\.title), label: "Dictation language")
            }
            GSDivider()
            GSToggleRow(symbol: "capsule", title: "Recorder", text: "A small floating pill with a live waveform while you speak.",
                        isOn: Binding(get: { RecorderPill.isEnabled }, set: { RecorderPill.isEnabled = $0 }))
            GSDivider()
            GSToggleRow(symbol: "text.viewfinder", title: "Check before writing", text: "Shows the text in a card by your cursor. Return writes it, Escape drops it. After 5 minutes unanswered it is copied, not written.",
                        isOn: Binding(get: { settings.previewBeforeInsert }, set: { settings.previewBeforeInsert = $0 }))
            GSDivider()
            GSToggleRow(symbol: "pause.circle", title: "Pause music while you speak",
                        isOn: Binding(get: { settings.pauseMedia }, set: { settings.pauseMedia = $0 }))
            GSDivider()
            GSToggleRow(symbol: "keyboard.badge.ellipsis", title: "Type instead of paste", text: "Slower, but works where \u{2318}V is blocked.",
                        isOn: Binding(get: { settings.alwaysType }, set: { settings.alwaysType = $0 }))
        }
        soundCard
        GSCard("Voice glow") {
            GSToggleRow(symbol: "sparkles", title: "Voice glow", text: "A soft glow on the recorder that rises with your voice and sweeps while it writes.",
                        isOn: Binding(get: { VoiceGlowSettings.shared.enabled }, set: { VoiceGlowSettings.shared.enabled = $0 }))
            GSDivider()
            GSRow(symbol: "paintpalette", title: "Colors") {
                HStack(spacing: 10) {
                    HStack(spacing: -4) {
                        ForEach(Array(VoiceGlowSettings.shared.variant.palette.enumerated()), id: \.offset) { _, rgb in
                            Circle().fill(Color(voiceGlow: rgb)).frame(width: 12, height: 12)
                        }
                    }
                    .accessibilityHidden(true)
                    GSPopup(selection: Binding(get: { VoiceGlowSettings.shared.variant.title },
                                               set: { title in VoiceGlowSettings.shared.variant = VoiceGlowVariant.allCases.first { $0.title == title } ?? .colorful }),
                            options: VoiceGlowVariant.allCases.map(\.title), label: "Voice glow colors")
                }
            }
        }
        GSCard("Microphone") {
            GSRow(symbol: "mic.circle", title: "Input") {
                GSPopup(selection: Binding(get: { micName(settings.microphoneUID) },
                                           set: { name in
                                               let labels = micLabels()
                                               if let index = labels.firstIndex(of: name) { settings.microphoneUID = tester.devices[index].uid }
                                               else if name == "System default" { settings.microphoneUID = nil }
                                           }),
                        options: micOptions, label: "Dictation microphone")
            }
            GSDivider()
            GSRow(symbol: "waveform.badge.mic", title: "Test", text: tester.problem ?? tester.verdict ?? (tester.running ? "Say a few words." : "Speak and watch the level move.")) {
                HStack(spacing: 12) {
                    LevelMeter(level: tester.level).frame(width: 110, height: 8)
                        .accessibilityLabel("Microphone level").accessibilityValue("\(Int(tester.level * 100)) percent")
                    Button(tester.running ? "Stop" : "Test microphone") {
                        if tester.running { tester.stop() } else { tester.start(uid: settings.microphoneUID) }
                    }.buttonStyle(GSButtonStyle())
                }
            }
        }
        .onAppear { Task { tester.devices = await Task.detached(priority: .userInitiated) { Microphones.all() }.value } } // CoreAudio queries can stall: never on main
        .onDisappear { tester.stop() }
        modesCard
        engineCard
        LanguagePacksCard()
        vocabularyCard
        historyCard
    }

    // MARK: Sounds

    @ViewBuilder private var soundCard: some View {
        GSCard("Sounds") {
            GSRow(symbol: "speaker.wave.2", title: "Start and stop sound", text: Self.cueDetail(settings.cueStyle)) {
                GSPopup(selection: Binding(get: { settings.cueStyle.title },
                                           set: { title in settings.cueStyle = DictationCueStyle(saved: title) }),
                        options: DictationCueStyle.allCases.map(\.title), label: "Dictation start and stop sound")
            }
            GSDivider()
            GSRow(symbol: "play.circle", title: "Preview", text: "Plays the start sound, then the stop sound.") {
                Button("Play") { DictationCuePlayer.preview() }
                    .buttonStyle(GSButtonStyle()).disabled(settings.cueStyle == .none)
            }
            GSDivider()
            GSRow(symbol: "speaker.wave.1", title: "Volume", text: "\(settings.cueVolume)%") {
                Slider(value: Binding(get: { Double(settings.cueVolume) }, set: { settings.cueVolume = Int($0.rounded()) }),
                       in: 0...100, step: 5)
                    .snapshotSafeSlider(value: Double(settings.cueVolume), in: 0...100)
                    .frame(width: 160)
                    .accessibilityLabel("Start and stop sound volume")
                    .accessibilityValue("\(settings.cueVolume) percent")
            }
        }
    }

    private static func cueDetail(_ style: DictationCueStyle) -> String {
        switch style {
        case .crystal: "Two soft glass notes, rising when you start and falling when you stop."
        case .softClick: "The classic Zeus click."
        case .glass: "A bright, clear tone."
        case .pop: "A short, soft bubble."
        case .airy: "A short warm blip, rising when you start and falling when you stop."
        case .none: "No sound when dictation starts or stops."
        }
    }

    /// One label per device, in device order. Two microphones with the same name stay distinguishable
    /// (and are always chosen by UID, never by name).
    private func micLabels() -> [String] {
        let devices = tester.devices
        return devices.enumerated().map { index, device in
            let twins = devices.filter { $0.name == device.name }.count
            return twins > 1 ? "\(device.name) (\(index + 1))" : device.name
        }
    }

    private var micOptions: [String] {
        var options = ["System default"] + micLabels()
        if let uid = settings.microphoneUID, !tester.devices.contains(where: { $0.uid == uid }) { options.append("Unavailable microphone") }
        return options
    }

    private func micName(_ uid: String?) -> String {
        guard let uid else { return "System default" }
        guard let index = tester.devices.firstIndex(where: { $0.uid == uid }) else { return "Unavailable microphone" }
        return micLabels()[index]
    }

    // MARK: Modes

    @ViewBuilder private var modesCard: some View {
        let modes = topBar?.dictationModes ?? DictationMode.builtIns
        GSCard("Modes") {
            Text("A mode decides how your words are written. Voice writes exactly what you said. The others tidy it with your own AI first.")
                .font(GS.rowText).foregroundStyle(GS.secondary).padding(.bottom, 4)
            ForEach(Array(modes.enumerated()), id: \.element.key) { index, mode in
                if index > 0 { GSDivider() }
                modeRow(mode)
                if page.editingKey == mode.key { editor(mode) }
            }
            if let draft = page.draftMode, !modes.contains(where: { $0.key == draft.key }) {
                GSDivider()
                editor(draft)
            }
            GSDivider()
            GSToggleRow(symbol: "app.badge", title: "Switch by app", text: "Uses the mode that lists the app in front, such as Mail or Slack.",
                        isOn: Binding(get: { settings.autoSwitch }, set: { settings.autoSwitch = $0 }))
            GSDivider()
            GSRow(symbol: "plus.circle", title: "New mode") {
                Button("Add a mode") { startEditing(DictationMode(key: "mode-\(Int(Date().timeIntervalSince1970))", name: "New mode", symbol: "sparkles", prompt: "Rewrite this dictation clearly. Keep every fact. Return only the result."), isNew: true) }
                    .buttonStyle(GSButtonStyle()).disabled(controller == nil)
            }
        }
    }

    private func modeRow(_ mode: DictationMode) -> some View {
        let selected = topBar?.selectedModeKey == mode.key
        let custom = !DictationMode.builtIns.contains { $0.key == mode.key }
        return GSRow(symbol: mode.symbol, title: mode.name, text: mode.usesAI ? "Tidied by your AI before it is written." : "Exactly what you said, with no AI rewrite. The speech engine below does the listening.") {
            HStack(spacing: 10) {
                if selected { GSStatus(ok: true, text: "In use") }
                else { Button("Use") { topBar?.selectedModeKey = mode.key }.buttonStyle(GSButtonStyle()).disabled(topBar == nil).accessibilityLabel("Use \(mode.name)") }
                Button("Edit") { page.editingKey == mode.key ? (page.editingKey = nil) : startEditing(mode, isNew: false) }
                    .buttonStyle(GSButtonStyle()).disabled(controller == nil).accessibilityLabel("Edit \(mode.name)")
                if custom {
                    Button("Remove") { controller?.deleteMode(key: mode.key) }.buttonStyle(GSButtonStyle()).disabled(controller == nil).accessibilityLabel("Remove \(mode.name)")
                }
            }
        }
    }

    private func startEditing(_ mode: DictationMode, isNew: Bool) {
        page.editingKey = mode.key
        page.draftMode = isNew ? mode : nil
        page.name = mode.name
        page.prompt = mode.prompt
    }

    private func editor(_ mode: DictationMode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Name", Binding(get: { page.name }, set: { page.name = $0 }))
            Text("Instructions (empty writes your words as they are)").font(GS.rowText).foregroundStyle(GS.secondary)
            TextEditor(text: Binding(get: { page.prompt }, set: { page.prompt = $0 }))
                .font(OB.font(13.5)).scrollContentBackground(.hidden).foregroundStyle(GS.text)
                .padding(8).frame(height: 96)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                .accessibilityLabel("Mode instructions")
            HStack(spacing: 10) {
                Button("Save mode") {
                    var edited = mode
                    edited.name = page.name.trimmingCharacters(in: .whitespaces).isEmpty ? mode.name : page.name
                    edited.prompt = page.prompt
                    controller?.saveMode(edited)
                    page.editingKey = nil
                    page.draftMode = nil
                }.buttonStyle(GSButtonStyle(prominent: true)).disabled(controller == nil)
                Button("Cancel") { page.editingKey = nil; page.draftMode = nil }.buttonStyle(GSButtonStyle())
            }
        }
        .padding(.bottom, 14)
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .snapshotSafeText(text.wrappedValue, placeholder: title)
            .font(OB.font(13.5)).foregroundStyle(GS.text)
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
            .accessibilityLabel(title)
    }

    // MARK: Engine

    private var engineCard: some View {
        SpeechEngineCard(title: "Speech engine", showsWhisperModel: true)
    }

    // MARK: Vocabulary and history

    @ViewBuilder private var vocabularyCard: some View {
        GSCard("Vocabulary") {
            Text("Names and words to listen for, separated by commas. Replacements fix what is heard: write one per line as heard -> written.")
                .font(GS.rowText).foregroundStyle(GS.secondary).padding(.bottom, 4)
            editorBox("Words", Binding(get: { page.wordsText }, set: { page.wordsText = $0 }), height: 64)
            editorBox("Replacements", Binding(get: { page.replacementsText }, set: { page.replacementsText = $0 }), height: 80)
            HStack(spacing: 10) {
                Button("Save vocabulary") {
                    guard let controller else { return }
                    let current = controller.vocabulary
                    let merged = VocabularyMerge.merged(edited: page.vocabulary(keeping: current), loaded: page.loadedVocabulary, current: current)
                    controller.vocabulary = merged
                    page.loadVocabulary(merged)
                }.buttonStyle(GSButtonStyle(prominent: true)).disabled(controller == nil)
            }
            .padding(.bottom, 14)
        }
        .onAppear { if let controller { page.loadVocabulary(controller.vocabulary) } }
    }

    private func editorBox(_ title: String, _ text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(OB.font(13, .semibold)).foregroundStyle(GS.text)
            TextEditor(text: text)
                .font(OB.font(13.5)).scrollContentBackground(.hidden).foregroundStyle(GS.text)
                .padding(8).frame(height: height)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                .accessibilityLabel(title)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder private var historyCard: some View {
        GSCard("History") {
            GSRow(symbol: "clock.arrow.circlepath", title: "Keep for", text: "Each dictation is saved on this Mac with its audio so you can write it again with another mode or engine.") {
                GSPopup(selection: Binding(get: { Self.keepTitle(settings.keepDays) }, set: { settings.keepDays = Self.keepDays(for: $0) }),
                        options: Self.keepChoices(including: settings.keepDays), label: "Keep history for")
            }
            GSDivider()
            GSRow(symbol: "list.bullet.rectangle", title: "History") {
                Button("Open history") { if let topBar { DictationHistoryWindow.shared.show(topBar: topBar) } }.buttonStyle(GSButtonStyle())
                    .disabled(topBar == nil)
            }
            if let recent = topBar?.dictationHistory.prefix(3), !recent.isEmpty {
                ForEach(Array(recent), id: \.id) { record in
                    GSDivider()
                    GSRow(title: record.result.count > 70 ? String(record.result.prefix(70)) + "\u{2026}" : record.result,
                          text: "\(record.modeName) \u{00B7} \(record.wordCount) words") {
                        Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record.result, forType: .string) }
                            .buttonStyle(GSButtonStyle()).accessibilityLabel("Copy this dictation")
                    }
                }
            }
        }
    }

    static let keepOptions = ["7 days", "30 days", "90 days", "Forever"]
    /// The real stored value, never a stand-in: a custom retention (say 14 days) shows as itself.
    static func keepTitle(_ days: Int) -> String { days <= 0 ? "Forever" : "\(days) days" }
    static func keepChoices(including days: Int) -> [String] {
        let current = keepTitle(days)
        return keepOptions.contains(current) ? keepOptions : [current] + keepOptions
    }
    static func keepDays(for title: String) -> Int { title == "Forever" ? 0 : Int(title.split(separator: " ")[0]) ?? 30 }
}

private struct LevelMeter: View {
    let level: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(GS.toggleOff)
                Capsule().fill(level > 0.95 ? Color.orange : OB.allowed).frame(width: proxy.size.width * level)
            }
        }
    }
}
