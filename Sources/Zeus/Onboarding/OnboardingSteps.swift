import AppKit
import ZeusCore
import SwiftUI

/// One step: the left column (or a centred block for the theme step) and its visual on the right.
struct OnboardingStepView: View {
    let step: OnboardingStep
    let flow: OnboardingFlow
    let services: OnboardingServices

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch step {
            case .theme:
                ThemeStep()
                    .frame(maxWidth: .infinity)
                    .offset(y: OB.contentMidY + nudge - OB.size.height / 2)
            default:
                column
                    .frame(width: OB.columnWidth, alignment: .topLeading)
                    .offset(x: OB.contentX, y: OB.headingTopY)
                placedVisual
            }
        }
        .frame(width: OB.size.width, height: OB.size.height)
    }

    @ViewBuilder private var placedVisual: some View {
        switch step {
        case .welcome:
            welcomeVisual
        case .murmure, .agents, .control, .reach:
            FilmCard(films: step.films).position(x: OB.visualCenterX, y: OB.contentMidY)
        case .day:
            DayIcons(pitch: DayStep.pitch, count: 3)
                .position(x: OB.visualCenterX, y: OnboardingChromeLayout.rowsMidY(count: 3, pitch: DayStep.pitch))
        case .halo:
            HaloPreviewCard(height: OnboardingChromeLayout.rowsBlock(count: 4, pitch: HaloStep.pitch).height)
                .position(x: OB.visualCenterX, y: OnboardingChromeLayout.rowsMidY(count: 4, pitch: HaloStep.pitch))
        case .sounds:
            SoundsPreviewTile(height: OnboardingChromeLayout.rowsBlock(count: SoundsStep.rowCount, pitch: SoundsStep.pitch).height)
                .position(x: OB.visualCenterX, y: OnboardingChromeLayout.rowsMidY(count: SoundsStep.rowCount, pitch: SoundsStep.pitch))
        case .theme:
            EmptyView()
        }
    }

    /// The hero panel beside the value points: top aligned with the heading, the living mascot (drawn by
    /// `OnboardingRoot`) centred in it.
    private var welcomeVisual: some View {
        let frame = OnboardingChromeLayout.welcomePreviewFrame()
        return WelcomeHero()
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }

    /// Per-step vertical correction: keep every step heading on the same baseline (QA round 16).
    private var nudge: CGFloat { 0 }

    @ViewBuilder private var column: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .murmure: MurmureStep(services: services)
        case .agents: AgentsStep(flow: flow, services: services)
        case .control: ControlStep()
        case .reach: ReachStep()
        case .day: DayStep(services: services)
        case .halo: HaloStep()
        case .sounds: SoundsStep(flow: flow, services: services)
        case .theme: EmptyView()
        }
    }

    @ViewBuilder private var visual: some View {
        switch step {
        case .welcome: WelcomeHero()
        case .murmure, .agents, .control, .reach: FilmCard(films: step.films)
        case .day: DayIcons(pitch: DayStep.pitch, count: 3)
        case .halo: HaloPreviewCard(height: OnboardingChromeLayout.rowsBlock(count: 4, pitch: HaloStep.pitch).height)
        case .sounds: SoundsPreviewTile(height: OnboardingChromeLayout.rowsBlock(count: SoundsStep.rowCount, pitch: SoundsStep.pitch).height)
        case .theme: EmptyView()
        }
    }
}

/// Title and subtitle, as on every Glance step.
struct StepHeading: View {
    let title: String
    let subtitle: String
    var centred = false
    @Environment(\.ob) private var ob
    var body: some View {
        VStack(alignment: centred ? .center : .leading, spacing: centred ? 9 : 12.5) {
            Text(title).font(centred ? OB.display(27) : OB.title).tracking(centred ? -1.1 : OB.titleTracking).foregroundStyle(ob.text)
                .accessibilityAddTraits(.isHeader)
            if !subtitle.isEmpty {
                Text(subtitle).font(centred ? OB.font(14.5) : OB.subtitle).foregroundStyle(ob.secondary)
                    .lineSpacing(4)
                    .multilineTextAlignment(centred ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(height: centred ? nil : 44, alignment: .topLeading)
    }
}

// MARK: 1 Welcome

/// The bindings as they are right now (both are recordable in Settings), so no step names a key by hand.
private enum OnboardingKeys {
    @MainActor static var talk: String { Preferences.shared.pushToTalk.title }
    @MainActor static var dictation: String { DictationSettings.shared.key?.title ?? "your dictation key" }
}

private struct WelcomeStep: View {
    @Environment(\.ob) private var ob
    static let points: [(symbol: String, title: String)] = [
        ("square.stack.3d.up", "Agents in the notch"),
        ("mic", "Talk, don't type"),
        ("sun.max", "Your day at a glance"),
    ]
    /// Distance between the value points (they run from the rows line to about 70 percent of the window).
    static let pitch: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(title: "Welcome to Zeus", subtitle: "")
                .frame(width: 420, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.points.enumerated()), id: \.offset) { _, point in
                    HStack(spacing: 16) {
                        Image(systemName: point.symbol).font(.system(size: 19, weight: .regular)).foregroundStyle(OB.blueText)
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ob.tile))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.title).font(OB.font(16, .semibold)).foregroundStyle(ob.text)
                        }
                    }
                    .frame(width: 420, height: Self.pitch, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, OnboardingChromeLayout.headingToRows)
        }
    }
}

/// The right half of the welcome step: a soft panel under a small notch, with the living mascot (drawn by
/// `OnboardingRoot` at the hero slot) centred in it. No film, no drop shadow.
struct WelcomeHero: View {
    @Environment(\.ob) private var ob
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [ob.tile, ob.tile.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(ob.tileStroke.opacity(0.7), lineWidth: 1))
            UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous)
                .fill(Color.black)
                .frame(width: 150, height: 30)
                .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous)
                    .strokeBorder(OB.blueLight.opacity(0.55), lineWidth: 1.2))
        }
        .accessibilityHidden(true)
    }
}

// MARK: 2 Murmure

private struct MurmureStep: View {
    let services: OnboardingServices
    @Environment(\.ob) private var ob
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(title: "Murmure", subtitle: "")
                .frame(width: 520, alignment: .leading)
            VStack(spacing: 0) {
                OBRow(symbol: "mic", title: "Microphone", text: "") {
                    OBAllowButton(granted: services.granted(.microphone), name: "Microphone") {
                        services.permissions.request(.microphone)
                    }
                }
                .frame(height: 62)
                OBDivider()
                OBRow(symbol: "accessibility", title: "Accessibility", text: "") {
                    OBAllowButton(granted: services.granted(.accessibility), name: "Accessibility") {
                        services.permissions.request(.accessibility)
                    }
                }
                .frame(height: 62)
                OBDivider()
                OBRow(symbol: "arrow.down.circle", title: "Murmure model", text: "", textWidth: 230) {
                    modelControl
                }
                .padding(.top, 14)
                if let problem = services.modelProblem, !services.modelReady, services.modelProgress == nil {
                    Text(problem).font(OB.font(12.5)).foregroundStyle(Color.red.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 430, alignment: .leading)
                        .padding(.top, 8)
                        .accessibilityLabel("Murmure model download failed. \(problem)")
                }
            }
            .padding(.top, 24)
        }
    }

    @ViewBuilder private var modelControl: some View {
        if services.modelReady {
            OBAllowButton(granted: true, name: "Murmure model") {}
        } else if let progress = services.modelProgress {
            HStack(spacing: 8) {
                ProgressView(value: progress).progressViewStyle(.linear).frame(width: 70).tint(OB.blueLight)
                Text("\(Int(progress * 100)) %").font(OB.font(13, .semibold)).foregroundStyle(ob.secondary).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Downloading the Murmure model, \(Int(progress * 100)) percent")
        } else {
            Button("Download") { services.prepareDictationModel() }
                .buttonStyle(OBOutlineButtonStyle())
                .accessibilityHint("Downloads the on-device dictation model.")
        }
    }
}

// MARK: 3 Your agents

private struct AgentsStep: View {
    let flow: OnboardingFlow
    let services: OnboardingServices
    @Environment(\.ob) private var ob
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(title: "Your agents", subtitle: "")
                .frame(width: 520, alignment: .leading)
            AgentSegmented(selection: Binding(get: { flow.agent }, set: { flow.agent = $0 }))
                .padding(.top, 23.5)
            let connected = services.isConnected(flow.agent)
            HStack(spacing: 10) {
                if connected {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                        Text("Connected").font(OB.font(14.5, .semibold))
                    }
                    .foregroundStyle(OB.allowed)
                    Button("Check again") { services.refresh() }
                        .buttonStyle(OBOutlineButtonStyle(height: 35, filled: false))
                } else {
                    Button("Connect") { services.connect(flow.agent) }
                        .buttonStyle(OBBlueButtonStyle())
                    Button("Check again") { services.refresh() }
                        .buttonStyle(OBOutlineButtonStyle(height: 35, filled: false))
                }
            }
            .padding(.top, 22.5)
            if flow.agent == .claude {
                Text("Claude Code only, not Claude Desktop chats yet.")
                    .font(OB.font(13)).foregroundStyle(ob.secondary).lineSpacing(1.5)
                    .frame(width: 430, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 13)
            }
            if let message = services.connectMessage {
                Text(message).font(OB.font(12.5)).foregroundStyle(ob.secondary).padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                OBRow(symbol: "bell", title: "Zeus alerts", text: "") {
                    OBAllowButton(granted: services.notificationsAllowed, name: "Zeus alerts") { services.allowNotifications() }
                }
                .frame(height: 62)
                OBDivider()
                OBRow(symbol: "externaldrive", title: "Full Disk Access", text: "") {
                    OBAllowButton(granted: services.fullDiskAccess, name: "Full Disk Access") { services.allowFullDiskAccess() }
                }
                .frame(height: 62)
                OBDivider()
                OBRow(symbol: "music.note", title: "Music and Spotify", text: "") {
                    OBAllowButton(granted: services.granted(.automation), name: "Music and Spotify") { services.requestAutomation() }
                }
                .frame(height: 62)
                if let message = services.automationMessage {
                    Text(message).font(OB.font(12.5)).foregroundStyle(ob.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 430, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 27)
        }
    }
}

/// Codex / Claude (133 x 24, blue selected segment).
private struct AgentSegmented: View {
    @Binding var selection: OnboardingFlow.AgentChoice
    @Environment(\.ob) private var ob
    var body: some View {
        HStack(spacing: 0) {
            ForEach(OnboardingFlow.AgentChoice.allCases, id: \.self) { choice in
                Button { selection = choice } label: {
                    Text(choice.rawValue).font(.system(size: 13.5))
                        .foregroundStyle(selection == choice ? .white : ob.text.opacity(0.9))
                        .frame(width: 66.5, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selection == choice ? OB.blue : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == choice ? [.isSelected] : [])
            }
        }
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ob.track))
        .animation(.easeInOut(duration: 0.18), value: selection)
    }
}

// MARK: 4 Stay in control

private struct ControlStep: View {
    static let pitch: CGFloat = 84
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(title: "Stay in control.", subtitle: "")
                .frame(width: 420, alignment: .leading)
            OBRowList(pitch: Self.pitch) {
                toggleRow("hand.raised", "Permission requests", Binding(get: { ExtraPreferences.shared.peekApprovals }, set: { ExtraPreferences.shared.peekApprovals = $0 }))
                toggleRow("checkmark.circle", "Finished tasks", Binding(get: { ExtraPreferences.shared.peekAgentDone }, set: { ExtraPreferences.shared.peekAgentDone = $0 }))
                toggleRow("exclamationmark.triangle", "Errors and stuck agents", SettingsStore.shared.boolBinding("notify.errors"))
            }
            .frame(width: 420)
            .padding(.top, OnboardingChromeLayout.headingToRows)
        }
    }

    private func toggleRow(_ symbol: String, _ title: String, _ isOn: Binding<Bool>) -> some View {
        OBRow(symbol: symbol, title: title, text: "") {
            Toggle(title, isOn: isOn).toggleStyle(OBToggleStyle()).accessibilityLabel(title)
        }
    }
}

// MARK: 5 Keys and displays

private struct ReachStep: View {
    static let pitch: CGFloat = 66
    @Environment(\.ob) private var ob
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(title: "Keys and displays.", subtitle: "")
                .frame(width: 420, alignment: .leading)
            OBRowList(pitch: Self.pitch) {
                OBRow(symbol: "mic", title: "Hold to talk, double-tap to latch", text: "") { keys(OnboardingKeys.talk) }
                OBRow(symbol: "keyboard", title: "Answer from the keyboard", text: "") { keys("\u{2303}\u{2325}Y  \u{2303}\u{2325}N  \u{2303}\u{2325}O") }
                OBRow(symbol: "display.2", title: "Every display", text: "") {
                    OBPopup(selection: SettingsStore.binding("notch.displays"), options: NotchDisplayMode.allCases.map(\.rawValue))
                        .accessibilityLabel("Show the notch on")
                }
                OBRow(symbol: "moon.zzz", title: "Insomnia", text: "") {
                    Toggle("Insomnia", isOn: SettingsStore.shared.boolBinding("insomnia.lidClosed"))
                        .toggleStyle(OBToggleStyle()).accessibilityLabel("Insomnia")
                }
            }
            .frame(width: 420)
            .padding(.top, OnboardingChromeLayout.headingToRows)
        }
    }

    private func keys(_ text: String) -> some View {
        Text(text).font(OB.font(13, .medium)).foregroundStyle(ob.secondary).lineLimit(1)
    }
}

// MARK: 6 Your day

private struct DayStep: View {
    let services: OnboardingServices
    /// Tall rows: each of the three app icons on the right sits level with its own row.
    static let pitch: CGFloat = 88
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(title: "Your day", subtitle: "")
                .frame(width: 420, alignment: .leading)
            OBRowList(pitch: Self.pitch) {
                OBRow(symbol: "cloud.sun", title: "Local weather", text: "") {
                    OBAllowButton(granted: services.locationAllowed, name: "Local weather") { services.allowLocation() }
                }
                OBRow(symbol: "calendar", title: "Calendar", text: "") {
                    OBAllowButton(granted: services.granted(.calendar), name: "Calendar") {
                        services.permissions.request(.calendar)
                    }
                }
                OBRow(symbol: "list.bullet.circle", title: "Reminders", text: "") {
                    OBAllowButton(granted: services.granted(.reminders), name: "Reminders") {
                        services.permissions.request(.reminders)
                    }
                }
            }
            .frame(width: 420)
            .padding(.top, OnboardingChromeLayout.headingToRows)
        }
    }
}

// MARK: 7 Theme

private struct ThemeStep: View {
    private var style: String { SettingsStore.shared.string("appearance.cardStyle") }
    @Environment(\.ob) private var ob
    static let choices = ["Glass", "Liquid Glass", "Physical"]

    var body: some View {
        VStack(spacing: 0) {
            StepHeading(title: "Choose your theme.", subtitle: "", centred: true)
            ThemePreview(style: style)
                .frame(width: 400, height: 240)
                .padding(.top, 24)
                .accessibilityLabel("Home and Music preview, \(style)")
            HStack(spacing: 12) {
                ForEach(Self.choices, id: \.self) { choice in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { SettingsStore.shared.set("appearance.cardStyle", choice) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: style == choice ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(style == choice ? Color.white : ob.text, style == choice ? OB.blueLight : ob.text)
                            Text(choice).font(OB.font(14.5, .semibold))
                        }
                        .foregroundStyle(style == choice ? OB.blueText : ob.text)
                        .frame(width: 142, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(style == choice ? ob.tile : ob.fieldFill))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(style == choice ? OB.blueLight : ob.fieldStroke, lineWidth: style == choice ? 1.5 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(style == choice ? [.isSelected] : [])
                }
            }
            .padding(.top, 22)
        }
    }
}

// MARK: 8 Halo

private struct HaloStep: View {
    static let pitch: CGFloat = 66
    @Environment(\.ob) private var ob

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(title: "Your signature of light", subtitle: "")
                .frame(width: 420, alignment: .leading)
            OBRowList(pitch: Self.pitch) {
                OBRow(symbol: "sparkles", title: "Light", text: "") { popup("Light", HaloChoices.styleTitle, HaloChoices.styles) }
                OBRow(symbol: "arrow.left.and.right", title: "Halo arm width", text: "") { popup("Halo arm width", SettingsStore.binding("halo.armWidth"), HaloChoices.armWidths) }
                OBRow(symbol: "play.circle", title: "Halo entrance", text: "") { popup("Halo entrance", HaloChoices.entranceTitle, HaloChoices.entrances) }
                OBRow(symbol: "slider.horizontal.3", title: "Light thickness", text: "") { thickness }
            }
            .frame(width: 420)
            .padding(.top, OnboardingChromeLayout.headingToRows)
        }
    }

    private func popup(_ title: String, _ value: Binding<String>, _ options: [String]) -> some View {
        OBPopup(selection: value, options: options).accessibilityLabel(title)
    }

    private var thickness: some View {
        HStack(spacing: 8) {
            OBTickSlider(value: Binding(get: { SettingsStore.shared.double("halo.thickness") }, set: { SettingsStore.shared.set("halo.thickness", String(Int($0))) }), range: 100...200, step: 5)
                .frame(width: 130)
                .accessibilityLabel("Light thickness")
            Text("\(Int(SettingsStore.shared.double("halo.thickness"))) %")
                .font(OB.font(13.5, .semibold)).foregroundStyle(ob.text).monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
    }
}

enum HaloChoices {
    /// Display titles, straight from the enums, so a picker can never offer a name the notch does not know.
    static let styles = HaloStyle.allCases.map(\.title)
    static let armWidths = ["Narrow", "Medium", "Wide", "Extra wide"]
    static let entrances = HaloEntrance.allCases.map(\.title)

    /// A binding that shows titles but stores the stable id in `halo.style`.
    @MainActor static var styleTitle: Binding<String> {
        Binding(get: { HaloStyle.resolve(SettingsStore.shared.string("halo.style")).title },
                set: { SettingsStore.shared.set("halo.style", HaloStyle.resolve($0).rawValue) })
    }

    /// Same for `halo.entrance`.
    @MainActor static var entranceTitle: Binding<String> {
        Binding(get: { HaloEntrance.resolve(SettingsStore.shared.string("halo.entrance")).title },
                set: { SettingsStore.shared.set("halo.entrance", HaloEntrance.resolve($0).rawValue) })
    }
}

// MARK: 9 Sounds

private struct SoundsStep: View {
    let flow: OnboardingFlow
    let services: OnboardingServices
    private var soundsOn: Bool { ExtraPreferences.shared.soundsOn }
    @Environment(\.ob) private var ob
    /// The feedback switch and the four cues; the preview tile on the right spans exactly these rows.
    static let rowCount = 5
    static let pitch: CGFloat = 62

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(title: "The sounds of Zeus", subtitle: "")
                .frame(width: 420, alignment: .leading)
            OBRowList(pitch: Self.pitch) {
                OBRow(symbol: "speaker.wave.2", title: "Sound feedback", text: "") {
                    Toggle("Sound feedback", isOn: Binding(get: { ExtraPreferences.shared.soundsOn }, set: { ExtraPreferences.shared.soundsOn = $0 }))
                        .toggleStyle(OBToggleStyle(size: .large)).accessibilityLabel("Sound feedback")
                }
                soundRow("Run start", "play.circle", SettingsStore.binding("sound.startStyle"), SoundStyles.runStart, .start)
                soundRow("Requests", "hand.raised", SettingsStore.binding("sound.approvalStyle"), SoundStyles.requests, .approval)
                soundRow("Your answer", "checkmark.bubble", SettingsStore.binding("sound.answerStyle"), SoundStyles.answer, .answer)
                soundRow("Completion", "checkmark.circle", SettingsStore.binding("sound.doneStyle"), SoundStyles.done, .done)
            }
            .frame(width: 420)
            .padding(.top, OnboardingChromeLayout.headingToRows)
        }
    }

    private func soundRow(_ title: String, _ symbol: String, _ value: Binding<String>, _ options: [String], _ event: ZeusSound.Event) -> some View {
        OBRow(symbol: symbol, title: title, text: "") {
            HStack(spacing: 8) {
                OBPopup(selection: value, options: options, width: 150).frame(width: 150).accessibilityLabel("\(title) sound")
                previewButton(event, title)
            }
            .disabled(!soundsOn)
            .opacity(soundsOn ? 1 : 0.45)
        }
    }

    private func previewButton(_ event: ZeusSound.Event, _ title: String) -> some View {
        Button { SoundStyles.preview(event) } label: {
            Image(systemName: "speaker.wave.2").font(.system(size: 12, weight: .medium)).foregroundStyle(OB.blueText)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ob.tile))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play the \(title.lowercased()) sound")
    }
}

// MARK: Row lists

@resultBuilder
enum OBRowBuilder {
    static func buildExpression<V: View>(_ row: V) -> AnyView { AnyView(row) }
    static func buildBlock(_ rows: AnyView...) -> [AnyView] { rows }
}

/// Rows on a fixed pitch with a hairline between them (the last row has none), so a step's right-hand
/// visual can be placed against the same grid (`OnboardingChromeLayout.rowCenterY`).
struct OBRowList: View {
    let pitch: CGFloat
    let rows: [AnyView]

    init(pitch: CGFloat, @OBRowBuilder rows: () -> [AnyView]) {
        self.pitch = pitch
        self.rows = rows()
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                rows[index].frame(height: pitch - 1)
                if index < rows.count - 1 { OBDivider() } else { Color.clear.frame(height: 1) }
            }
        }
    }
}

// MARK: Shared controls

/// Native-looking pop-up. Like NSPopUpButton, it is as wide as its longest option.
struct OBPopup: View {
    @Binding var selection: String
    let options: [String]
    /// A fixed width where Glance's control is wider than its longest name.
    var width: CGFloat? = nil
    @Environment(\.ob) private var ob
    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    if option == selection { Label(option, systemImage: "checkmark") } else { Text(option) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    if width == nil { ForEach(options, id: \.self) { Text($0).hidden() } }
                    Text(selection)
                }
                .frame(maxWidth: width == nil ? nil : .infinity, alignment: .leading)
                .font(.system(size: 14.5))
                .foregroundStyle(ob.text)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(ob.text)
            }
            .padding(.leading, 12).padding(.trailing, 9)
            .frame(width: width, height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ob.popup))
            .fixedSize()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Glance's thickness slider: blue fill, round thumb, a row of tick dots underneath.
struct OBTickSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @Environment(\.ob) private var ob

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(ob.track).frame(height: 6)
                Capsule().fill(OB.toggleOn).frame(width: max(6, width * fraction), height: 6)
                HStack(spacing: 0) {
                    ForEach(0...Int((range.upperBound - range.lowerBound) / step), id: \.self) { _ in
                        Circle().fill(ob.secondary.opacity(0.35)).frame(width: 1.5, height: 1.5).frame(maxWidth: .infinity)
                    }
                }
                .offset(y: 7)
                Circle().fill(Color(rgb: 223, 224, 224)).frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(OB.toggleOn.opacity(fraction < 0.02 ? 0.35 : 0), lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .offset(x: (width - 20) * fraction)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let raw = range.lowerBound + Double(min(max(drag.location.x / width, 0), 1)) * (range.upperBound - range.lowerBound)
                value = (raw / step).rounded() * step
            })
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityValue("\(Int(value)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step * 2)
            case .decrement: value = max(range.lowerBound, value - step * 2)
            @unknown default: break
            }
        }
    }
}
