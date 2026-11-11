import AppKit
import Observation
import SwiftUI

/// First-run setup matching Glance's 960 x 760 flow, with a living gold mascot on every
/// step, purple lighting, and a real interactive action per step (ONBOARDING EXPERIENCE BAR).
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome, theme, agents, day, permissions, murmure, learn
    }

    var step: Step = .welcome
    /// Glass vs Physical (Glance O2).
    var themeChoice: String = "Glass"
    /// Set when push-to-talk is held during a later step.
    var heardKey = false
    /// Interactive progress flags (each step does something real).
    var waved = false
    var themePreviewed = false
    var agentsToggled = false
    var dayTapped = false
    var nameDraft = ""
    var celebrated = false
    var mascotPose: LivingPose = .welcome
    var celebrate = false

    var poseForStep: LivingPose {
        if celebrate || celebrated { return .celebrate }
        switch step {
        case .welcome: return waved ? .grateful : .welcome
        case .theme: return themePreviewed ? .curious : .guiding
        case .agents: return agentsToggled ? .working : .approval_wait
        case .day: return dayTapped ? .organizing : .guiding
        case .permissions: return .approval_wait
        case .murmure: return heardKey ? .listening : .curious
        case .learn: return nameDraft.isEmpty ? .idle : .typing
        }
    }

    func react(_ pose: LivingPose, celebrate: Bool = false) {
        mascotPose = pose
        if celebrate {
            self.celebrate = true
            celebrated = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.celebrate = false
            }
        }
    }
}

struct OnboardingView: View {
    let model: OnboardingModel
    let permissions: PermissionsModel
    let preferences: Preferences
    let watchDemo: () -> Void
    let finish: () -> Void

    var body: some View {
        ZStack {
            GlassBackdrop(tint: Theme.accent)
            purpleSweep
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 28) {
                    LivingMascot(pose: model.poseForStep, size: 200, celebrate: model.celebrate)
                        .padding(.top, 12)
                        .accessibilityHint("Zeus guides each step. Hover to say hi.")
                    Group {
                        switch model.step {
                        case .welcome: welcome
                        case .theme: themeStep
                        case .agents: agentsStep
                        case .day: dayStep
                        case .permissions: PermissionsStep(permissions: permissions)
                        case .murmure: murmureStep
                        case .learn: learnStep
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
                    .id(model.step)
                }
                .padding(.horizontal, 40)
                .padding(.top, 28)
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: model.step)

                HStack {
                    Button("Back") { back() }
                        .buttonStyle(GlassButtonStyle(kind: .quiet, compact: true))
                        .opacity(model.step == .welcome ? 0 : 1)
                        .disabled(model.step == .welcome)
                    Spacer()
                    StepDots(current: model.step.rawValue, count: OnboardingModel.Step.allCases.count)
                    Spacer()
                    footerButtons
                }
                .padding(24)
            }
        }
        .frame(width: 960, height: 760)
        // The environment value also reaches offscreen renders (snapshots); the preference only the window.
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: model.step) { _, _ in
            model.mascotPose = model.poseForStep
        }
    }

    private var purpleSweep: some View {
        TimelineView(.animation(minimumInterval: Motion.reduced ? 1 : 1 / 30, paused: Motion.reduced)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            LinearGradient(
                colors: [Theme.accentDeep.opacity(0.0), Theme.glow.opacity(0.18), Theme.accent.opacity(0.0)],
                startPoint: UnitPoint(x: CGFloat((sin(t * 0.35) + 1) / 2), y: 0),
                endPoint: UnitPoint(x: CGFloat((cos(t * 0.28) + 1) / 2), y: 1)
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: Steps

    private var welcome: some View {
        OnboardStep(title: "Hi, I’m Zeus.",
                    text: "Wave back, then we’ll set up your notch, agents and voice together.") {
            Button {
                model.waved = true
                model.react(.grateful)
            } label: {
                Label(model.waved ? "Nice to meet you" : "Wave to Zeus", systemImage: model.waved ? "hand.wave.fill" : "hand.wave")
            }
            .buttonStyle(GlassButtonStyle(kind: .primary))
            .accessibilityHint("Zeus waves back when you press this.")
            HStack(alignment: .top, spacing: 28) {
                welcomePill(symbol: "waveform", title: "Murmure", text: "Dictate anywhere.")
                welcomePill(symbol: "bolt.fill", title: "Your agents", text: "Follow runs from the notch.")
                welcomePill(symbol: "sun.max.fill", title: "Your day", text: "Calendar, weather, focus.")
            }
            .padding(.top, 8)
        }
    }

    private func welcomePill(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 8) {
            // Fixed icon box: SF Symbols differ in height, so titles line up across the row.
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.glow)
                .frame(height: 30)
            Text(title).font(.headline).foregroundStyle(Glass.text)
            Text(text).font(.callout).foregroundStyle(Glass.secondary).multilineTextAlignment(.center)
        }
        .frame(width: 150)
    }

    private var themeStep: some View {
        OnboardStep(title: "Pick a look",
                    text: "Glass frosts every Home card. Physical feels like a small device. Tap a look to preview the purple light.") {
            HStack(spacing: 14) {
                themeCard("Glass", symbol: "rectangle.on.rectangle.angled")
                themeCard("Physical", symbol: "button.programmable")
            }
            Text(model.themePreviewed ? "Purple lighting stays either way. Gold stays on Zeus." : "Choose one to continue.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func themeCard(_ name: String, symbol: String) -> some View {
        let selected = model.themeChoice == name
        return Button {
            model.themeChoice = name
            model.themePreviewed = true
            SettingsStore.shared.set("appearance.cardStyle", name == "Physical" ? "Physical" : "Liquid Glass")
            model.react(.curious)
        } label: {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.accent.opacity(selected ? 0.35 : 0.12))
                    .overlay(
                        Image(systemName: symbol).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.glow)
                    )
                    .frame(width: 160, height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : Color.white.opacity(0.12), lineWidth: selected ? 2 : 1))
                Text(name).font(.headline)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(name) theme\(selected ? ", selected" : "")")
    }

    private var agentsStep: some View {
        OnboardStep(title: "Your agents",
                    text: "Flip a switch for Claude Code or Codex. Zeus waits with open palms until you decide. Nothing advances on a timer.") {
            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "zeus.hooks.claude.wanted") },
                set: {
                    UserDefaults.standard.set($0, forKey: "zeus.hooks.claude.wanted")
                    model.agentsToggled = true
                    model.react($0 ? .working : .approval_wait)
                }
            )) { Text("Claude Code hooks") }
            .toggleStyle(.switch)
            .tint(Theme.accent)
            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "zeus.hooks.codex.wanted") },
                set: {
                    UserDefaults.standard.set($0, forKey: "zeus.hooks.codex.wanted")
                    model.agentsToggled = true
                    model.react($0 ? .working : .approval_wait)
                }
            )) { Text("Codex hooks") }
            .toggleStyle(.switch)
            .tint(Theme.accent)
            Text("No extra macOS access is requested on this page.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var dayStep: some View {
        OnboardStep(title: "Your day",
                    text: "Tap Allow on a row: Calendar, Reminders or Weather. Zeus organises as each one lights up.") {
            interactivePermission("Calendar", kind: .calendar)
            interactivePermission("Reminders", kind: .reminders)
            Button {
                model.dayTapped = true
                model.react(.organizing)
            } label: {
                Label("Preview Today cards", systemImage: "sun.horizon.fill")
            }
            .buttonStyle(GlassButtonStyle(kind: .quiet))
            Text("Weather uses a city you type in Settings; Location stays optional.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func interactivePermission(_ name: String, kind: PermissionsModel.Kind) -> some View {
        let on = permissions.granted[kind] == true
        return HStack {
            PermissionLine(name: name, granted: on)
            Spacer()
            Button(on ? "On" : "Allow") {
                model.dayTapped = true
                model.react(on ? .success : .approval_wait)
                permissions.request(kind)
            }
            .buttonStyle(GlassButtonStyle(kind: on ? .quiet : .primary, compact: true))
            .disabled(on)
        }
    }

    private var murmureStep: some View {
        OnboardStep(title: "Try Murmure",
                    text: "Hold \(preferences.pushToTalk.title) and say anything. Zeus listens live. Speech stays on this Mac unless you pick a cloud engine later.") {
            ShortcutRecorderButton(shortcut: preferences.pushToTalk, onChange: { preferences.pushToTalk = $0 }, accessibilityName: "Talk key")
            PermissionLine(name: "Microphone", granted: permissions.granted[.microphone] == true)
            PermissionLine(name: "Speech Recognition", granted: permissions.granted[.speech] == true)
            PermissionLine(name: "Accessibility", granted: permissions.granted[.accessibility] == true)
            Button {
                model.heardKey = true
                model.react(.listening)
                Task {
                    await permissions.requestVoice()
                    if permissions.granted[.accessibility] != true {
                        permissions.requestAccessibility()
                        PermissionsModel.Kind.accessibility.settingsURL.map { NSWorkspace.shared.open($0) }
                    }
                }
            } label: {
                Label(model.heardKey ? "Listening ready" : "Enable voice and try it", systemImage: "waveform")
            }
            .buttonStyle(GlassButtonStyle(kind: .primary))
        }
    }

    private var learnStep: some View {
        OnboardStep(title: "You’re set",
                    text: "Type your name so Zeus can greet you. Then open the notch. Approvals, to-dos and Home cards live there.") {
            TextField("Your name", text: Binding(
                get: { model.nameDraft },
                set: {
                    model.nameDraft = $0
                    model.react($0.isEmpty ? .idle : .typing)
                    UserDefaults.standard.set($0, forKey: "aboutYou.name")
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 280)
            Button("Teach Zeus About You…") {
                model.react(.guiding)
                AboutYouWindow.shared.show()
            }
            .accessibilityHint("Your name, your work and your notes folder. Nothing leaves this Mac.")
            Button("Watch Demo", action: watchDemo)
            Button {
                model.react(.celebrate, celebrate: true)
            } label: {
                Label("Celebrate with Zeus", systemImage: "party.popper.fill")
            }
            // Done is the one primary action on this step.
            .buttonStyle(GlassButtonStyle(kind: .secondary))
        }
    }

    // MARK: Footer

    private func back() {
        guard let previous = OnboardingModel.Step(rawValue: model.step.rawValue - 1) else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { model.step = previous }
    }

    private func advance() {
        if let next = OnboardingModel.Step(rawValue: model.step.rawValue + 1) {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { model.step = next }
        } else {
            model.react(.celebrate, celebrate: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { finish() }
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        Button("Set up later", action: finish)
            .buttonStyle(GlassButtonStyle(kind: .quiet, compact: true))
        Button(model.step == .learn ? "Done" : "Continue") {
            switch model.step {
            case .welcome:
                if !model.waved { model.waved = true; model.react(.grateful) }
                advance()
            case .theme:
                if !model.themePreviewed { model.themePreviewed = true }
                advance()
            case .murmure:
                Task {
                    if permissions.granted[.accessibility] != true {
                        permissions.requestAccessibility()
                        PermissionsModel.Kind.accessibility.settingsURL.map { NSWorkspace.shared.open($0) }
                    }
                    await permissions.requestVoice()
                    model.heardKey = true
                    advance()
                }
            case .learn:
                model.react(.celebrate, celebrate: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { finish() }
            default:
                advance()
            }
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(GlassButtonStyle(kind: .primary, compact: true))
    }
}

private struct OnboardStep<Extra: View>: View {
    let title: String
    let text: String
    @ViewBuilder let extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Glass.text)
                .accessibilityAddTraits(.isHeader)
            Text(text).foregroundStyle(Glass.secondary).fixedSize(horizontal: false, vertical: true)
            extra
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

private struct PermissionLine: View {
    let name: String
    let granted: Bool

    var body: some View {
        Label {
            Text("\(name): \(granted ? "On" : "Off")")
        } icon: {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? Theme.leaf : Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StepDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Theme.accent : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
