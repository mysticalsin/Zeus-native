import AppKit
import SwiftUI
import ZeusCore

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
            GSToggleRow(symbol: "bolt", title: "Fast path", text: "Simple commands (open an app, volume, timers, to-dos, Beamer) run the moment you finish speaking. Off sends every command to the AI.",
                        isOn: store.boolBinding("fastPath.enabled"))
            GSInfo(text: "Which engine understands you, and its monthly cost cap, are on the Engine page.")
        }
        GSCard("Teleprompter") {
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
            GSToggleRow(symbol: "globe", title: "Let Zeus work in Chrome", text: "Web tasks you ask for, step by step, with a card you can stop. Passwords and card fields are always left to you.",
                        isOn: store.boolBinding("browserAgent.enabled"))
            GSDivider()
            GSRow(symbol: "list.number", title: "Most steps per task", text: "It stops and tells you when it runs out.") {
                GSPopup(selection: store.stringBinding("browserAgent.maxSteps"), options: FeatureSettings.browserStepChoices.map(String.init))
            }
            GSDivider()
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
        SpeakerRecognitionCard()
        GSCard("Research") {
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
