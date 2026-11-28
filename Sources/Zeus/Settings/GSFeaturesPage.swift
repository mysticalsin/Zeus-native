import AppKit
import SwiftUI
import ZeusCore

/// The fast path speaks whether simple commands run at once. It does not run a command or change the switch.
enum FastPathVoice {
    static var speakPath: () -> Void = {}
}

/// The Teleprompter card speaks which of its five switches are on. It does not change them.
enum PrompterSetupVoice {
    static var speakSetup: () -> Void = {}
}

/// The Browser agent card speaks whether it may work, the step limit, and which browser. It does not start a task.
enum BrowserAgentVoice {
    static var speakAgent: () -> Void = {}
}

/// The extra ask-words speak the count and the built-in list. The words stay unspoken, and no task starts.
enum AskWordsVoice {
    static var speakAsk: () -> Void = {}
}

/// The Coding in the terminal card speaks the agent and the terminal. It does not start a session.
enum CodingSetupVoice {
    static var speakSetup: () -> Void = {}
}

/// The Research card speaks the depth and whether reports use the default folder. It does not start research.
enum ResearchSetupVoice {
    static var speakSetup: () -> Void = {}
}

/// The Scribe card speaks when a meeting starts and what holds an automatic start. It does not start a meeting.
enum ScribeSetupVoice {
    static var speakSetup: () -> Void = {}
}

/// The model cap speaks the Sonnet ceiling and whether a pin is saved. The pin text stays unspoken.
enum ModelCapVoice {
    static var speakCap: () -> Void = {}
}

/// Settings › Features: a switch and the options for the things Zeus does on its own.
@MainActor
struct FeaturesSettingsPage: View {
    private var store: SettingsStore { .shared }
    @AppStorage(CodingTool.preferenceKey) private var codingTool = ""
    @AppStorage(TerminalApp.preferenceKey) private var terminal = ""
    @AppStorage("prompter.followPresentation") private var followPresentation = false
    @AppStorage("prompter.followAdvances") private var advanceSlides = false
    @AppStorage("prompterWindow.private") private var hideFromSharing = true
    @AppStorage("prompterWindow.mirror") private var mirror = false
    @AppStorage("prompterWindow.countdown") private var countdown = true

    var body: some View {
        GSPageHeading(section: .features, subtitle: "What Zeus does on its own, and how far it may go.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Instant commands") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the fast path is set") { FastPathVoice.speakPath() }
            }
            GSToggleRow(symbol: "bolt", title: "Fast path", text: "Simple commands (open an app, volume, timers, to-dos, Beamer) run the moment you finish speaking. Off sends every command to the AI.",
                        isOn: store.boolBinding("fastPath.enabled"))
            GSInfo(text: "Which engine understands you, and its monthly cost cap, are on the Engine page.")
        }
        GSCard("Teleprompter") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the prompter is set") { PrompterSetupVoice.speakSetup() }
            }
            GSToggleRow(symbol: "play.rectangle", title: "Follow my presentation", text: "Opens the prompter on its own when a Keynote or PowerPoint slideshow starts, with each slide\u{2019}s notes.",
                        isOn: prompter($followPresentation))
            GSDivider()
            GSToggleRow(symbol: "forward.end", title: "Advance slides when I finish their notes", text: "Voice-follow moves to the next slide. Off while you use a clicker.", isOn: prompter($advanceSlides))
            GSDivider()
            GSToggleRow(symbol: "eye.slash", title: "Hide the prompter from screen sharing", text: "You see it; shares and recordings don\u{2019}t.", isOn: prompter($hideFromSharing))
            GSDivider()
            GSToggleRow(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", title: "Mirror the text", text: "For a prompter glass.", isOn: prompter($mirror))
            GSDivider()
            GSToggleRow(symbol: "timer", title: "Count down before rolling", text: "A short countdown before the text starts scrolling, so you can get ready.", isOn: prompter($countdown))
        }
        GSCard("Browser agent") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the browser agent is set") { BrowserAgentVoice.speakAgent() }
            }
            GSToggleRow(symbol: "globe", title: "Let Zeus work in Chrome", text: "Web tasks you ask for, step by step, with a card you can stop. Passwords and card fields are always left to you.",
                        isOn: store.boolBinding("browserAgent.enabled"))
            GSDivider()
            GSRow(symbol: "list.number", title: "Most steps per task", text: "It stops and tells you when it runs out.") {
                GSPopup(selection: store.stringBinding("browserAgent.maxSteps"), options: FeatureSettings.browserStepChoices.map(String.init))
            }
            GSDivider()
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say what always asks") { AskWordsVoice.speakAsk() }
            }
            GSRow(symbol: "hand.raised", title: "Always ask before", text: "Words on a button or link, separated by commas. Buying, sending, deleting and posting always ask already.") {
                GSTextInput(text: store.stringBinding("browserAgent.alwaysAsk"), placeholder: "e.g. apply, invite", label: "Always ask before")
            }
            GSDivider()
            GSRow(symbol: "macwindow", title: "Browser for the agent", text: "Your Chrome uses the Zeus extension and your own logins. A separate browser has its own profile and never touches your Chrome.") {
                GSPopup(selection: store.stringBinding("browserAgent.backend"), options: FeatureSettings.browserBackendChoices)
            }
            GSDivider()
            if BrowserAgentBackendKind.resolve(setting: store.string("browserAgent.backend")) == .separate {
                GSBrowserUseRows()
            } else {
                GSInfo(text: "Choose the separate browser to set it up. You can also run one task in it with: zeus browse --separate \"<goal>\".")
            }
        }
        GSCard("Coding in the terminal") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how coding is set") { CodingSetupVoice.speakSetup() }
            }
            GSRow(symbol: "chevron.left.forwardslash.chevron.right", title: "Default coding agent", text: "Used when you say \u{201C}fix the login bug in zeus\u{201D} without naming one.") {
                GSPopup(selection: Binding(get: { CodingTool(rawValue: codingTool)?.title ?? CodingTool.claude.title },
                                           set: { title in codingTool = (CodingTool.allCases.first { $0.title == title } ?? .claude).rawValue }),
                        options: CodingTool.allCases.map(\.title))
            }
            GSDivider()
            GSRow(symbol: "terminal", title: "Terminal app", text: "Automatic uses the one you have open, then Ghostty, iTerm, Warp, then Terminal.") {
                GSPopup(selection: Binding(get: { TerminalApp(rawValue: terminal)?.title ?? "Automatic" },
                                           set: { title in terminal = TerminalApp.allCases.first { $0.title == title }?.rawValue ?? "" }),
                        options: ["Automatic"] + TerminalApp.allCases.map(\.title))
            }
        }
        scribeCard
        SpeakerRecognitionCard()
        GSCard("Research") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how research is set") { ResearchSetupVoice.speakSetup() }
            }
            GSRow(symbol: "magnifyingglass", title: "Depth", text: "Quick takes a few searches. Deep reads many sources and takes minutes. You can always say \u{201C}deep research\u{201D}.") {
                GSPopup(selection: store.stringBinding("research.depth"), options: FeatureSettings.researchDepthChoices)
            }
            GSDivider()
            GSRow(symbol: "folder", title: "Save reports in", text: folderText) {
                HStack(spacing: 8) {
                    Button("Choose") { chooseFolder() }.buttonStyle(GSButtonStyle())
                    if !store.string("research.folder").isEmpty { Button("Default") { store.set("research.folder", "") }.buttonStyle(GSButtonStyle()) }
                }
            }
        }
        GSCard("Models Zeus uses") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the model cap") { ModelCapVoice.speakCap() }
            }
            ForEach(Array(RouterEngine.allCases.enumerated()), id: \.element) { index, engine in
                if index > 0 { GSDivider() }
                HStack(spacing: 0) {
                    EngineBrandLogo(agentLabel: engine.title, size: 20, tint: GS.text)
                        .frame(width: 42, alignment: .leading).accessibilityHidden(true)
                    GSRow(title: engine.title, text: "Uses a quick model for simple asks and a deeper one for harder ones.")
                }
            }
            GSInfo(text: "Zeus acts with Haiku, or Sonnet at most, and the same size on every other engine. Your own coding sessions keep their own models.")
            GSDetails(text: modelDetails)
        }
    }

    private var scribeCard: some View {
        ScribeAutoStartCard(
            selection: store.stringBinding(ScribeAutoStartMode.settingID),
            block: store.autoStartBlock(),
            allow: { block in
                if block == .microphoneDenied { ScribeSettingsLink.open(pane: "Privacy_Microphone") } else { store.askForMicrophone() }
            })
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Coming back from System Settings after Allow: read the microphone again.
            store.microphoneMayHaveChanged()
        }
    }

    /// The exact model names and the pin override: useful to a person debugging, not part of the normal page.
    private var modelDetails: String {
        let lines = RouterEngine.allCases.map { engine -> String in
            let models = ModelCap.describe(engine)
            return "\(engine.title): quick \(models.fast), deep \(models.deep)"
        }
        return lines.joined(separator: "\n") + "\n\nA provider that renames models can be pinned with a modelCap.<engine>.<fast|deep> default. Anything larger than Sonnet is refused."
    }

    private var folderText: String {
        let path = store.string("research.folder")
        return path.isEmpty ? "Your second brain\u{2019}s ZEUS/Research, else Documents/Zeus Research." : ProjectIndex.tilde(path)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save here"
        if panel.runModal() == .OK, let url = panel.url { store.set("research.folder", url.path) }
    }

    /// A prompter switch: written, then an open prompter and the slideshow watcher pick it up.
    private func prompter(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0; PrompterHub.shared.settingsChanged() })
    }
}

/// The text box the Settings pages share.
struct GSTextInput: View {
    @Binding var text: String
    var placeholder = ""
    let label: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .snapshotSafeText(text, placeholder: placeholder)
            .font(OB.font(13.5)).foregroundStyle(GS.text)
            .padding(.horizontal, 10).frame(width: 260, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
            .accessibilityLabel(label)
    }
}

/// Scribe's one row, "When a meeting starts", and the row that names what blocks an automatic start, if anything.
/// It draws what it is given: the page supplies the choice, the block and the Allow action.
struct ScribeAutoStartCard: View {
    let selection: Binding<String>
    let block: ScribeAutoStartBlock?
    let allow: (ScribeAutoStartBlock) -> Void

    var body: some View {
        let mode = ScribeAutoStartMode.parse(selection.wrappedValue)
        GSCard("Scribe") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how Scribe is set") { ScribeSetupVoice.speakSetup() }
            }
            GSRow(symbol: "calendar.badge.clock", title: "When a meeting starts") {
                GlassSegmented(options: ScribeAutoStartMode.allCases.map { ($0.title, $0.title) }, selection: selection)
                    .padding(.trailing, 13.5)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("When a meeting starts")
                    .accessibilityValue(mode.title)
            }
            if mode == .automatic, let block, let words = ScribeMeetingCardText.reason(block) {
                GSDivider()
                GSRow(symbol: block == .firstRecordingOwed ? "record.circle" : "mic.slash", title: words) {
                    if block == .microphoneNotAsked || block == .microphoneDenied {
                        Button("Allow") { allow(block) }
                            .buttonStyle(GSButtonStyle())
                            .accessibilityLabel("Allow microphone")
                            .padding(.trailing, 13.5)
                    }
                }
            }
        }
    }
}
