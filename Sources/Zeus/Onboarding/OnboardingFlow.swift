import AppKit
import ZeusCore
import Observation
import SwiftUI

/// The nine welcome-guide steps. Glance's seven, with its learn films folded in: the intro plays on the
/// welcome step, "control" shows approve and previews, and "reach" shows shortcuts and everywhere.
enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, murmure, agents, control, reach, day, theme, halo, sounds

    var title: String {
        switch self {
        case .welcome: "Welcome to Zeus"
        case .murmure: "Murmure"
        case .agents: "Your agents"
        case .control: "Stay in control."
        case .reach: "Keys and displays."
        case .day: "Your day"
        case .theme: "Choose your theme."
        case .halo: "Your signature of light."
        case .sounds: "The sounds of Zeus."
        }
    }

    /// The films this step plays in its card, in order (more than one plays as a loop of the list).
    var films: [OnboardingFilm] {
        switch self {
        case .welcome: [.intro]
        case .murmure: [.murmure]
        case .agents: [.running]
        case .control: [.approve, .previews]
        case .reach: [.shortcuts, .everywhere]
        case .day, .theme, .halo, .sounds: []
        }
    }
}

/// How the guide moves between steps: a spring of about half a second that carries the mascot to its
/// next place, a light sweep across the window and a slow parallax of the watermark. Reduce Motion
/// replaces all of it with a short crossfade.
enum OnboardingTransition {
    enum Style: Equatable, Sendable { case choreographed, crossfade }

    /// Seconds the choreographed move takes (spring settling time, sweep, dash fill).
    static let duration = 0.52
    /// The light sweep runs a touch longer than the spring so it clears the window.
    static let sweepDuration = 0.56
    static let crossfadeDuration = Motion.crossfadeDuration
    /// How far each step shifts the watermark (pt), against the direction of travel.
    static let parallaxPerStep: CGFloat = 14
    /// Sideways travel of the incoming and outgoing step (pt).
    static let slide: CGFloat = 26

    static func style(reduceMotion: Bool) -> Style { reduceMotion ? .crossfade : .choreographed }

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: crossfadeDuration) : .spring(duration: duration, bounce: 0.12)
    }

    static func sweepAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: sweepDuration)
    }

    static func usesSweep(reduceMotion: Bool) -> Bool { !reduceMotion }

    static func watermarkShift(step: Int, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : -CGFloat(step) * parallaxPerStep
    }

    /// Step content: slides a little with the move, or simply fades with Reduce Motion.
    static func content(direction: Int, reduceMotion: Bool) -> AnyTransition {
        guard style(reduceMotion: reduceMotion) == .choreographed else { return .opacity }
        let travel = slide * CGFloat(direction)
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: travel)),
                           removal: .opacity.combined(with: .offset(x: -travel)))
    }

    @MainActor static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// The guide's earcons: the soft check on each step and Zeus's success sound at the end. Both obey the
/// Sound feedback switch (the one on the last step and in Settings).
enum OnboardingSound: CaseIterable, Sendable {
    case advance, finish

    var slot: SoundSlot { self == .advance ? .todo : .done }

    @MainActor static var enabled: Bool { ExtraPreferences.shared.soundsOn && !MeetingState.active }

    @MainActor func play() {
        guard Self.enabled else { return }
        ZeusSound.play(slot: slot, style: self == .finish ? ZeusSound.Event.done.name : nil)
    }
}

/// State of the guide. The current step survives a quit (Glance keeps
/// NotchPilot.onboarding.currentStep); finishing sets `onboarding.completed`.
@MainActor
@Observable
final class OnboardingFlow {
    static let stepKey = "zeus.onboarding.currentStep"
    static let completedKey = "zeus.onboarding.completed"

    var step: OnboardingStep {
        didSet { if !TopBarStyle.isSnapshot { UserDefaults.standard.set(step.rawValue, forKey: Self.stepKey) } }
    }
    /// +1 going forward, -1 going back; set just before the step changes so the outgoing view slides the right way.
    private(set) var direction = 1
    /// 0 to 1 while the light sweep crosses the window.
    var sweep = 0.0
    /// The mascot's wake-up (welcome step, first appearance).
    private(set) var wake: OnboardingStep.Wake
    /// Agents step: which agent's connection is shown.
    var agent: AgentChoice = .codex
    var detailsOpen = false
    var featuresOpen = false
    /// Plays a cue (tests replace it).
    @ObservationIgnored var playSound: (OnboardingSound) -> Void = { $0.play() }

    enum AgentChoice: String, CaseIterable { case codex = "Codex", claude = "Claude" }

    init() {
        let start = OnboardingStep(rawValue: UserDefaults.standard.integer(forKey: Self.stepKey)) ?? .welcome
        step = start
        wake = start == .welcome && !OnboardingTransition.reduceMotion && !TopBarStyle.isSnapshot ? .asleep : .awake
    }

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey) || UserDefaults.standard.bool(forKey: "didOnboard")
    }

    var mascotPose: LivingPose { step.mascotPose(wake: wake) }

    func next() {
        guard let following = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        go(following)
    }

    func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        go(previous)
    }

    func go(_ target: OnboardingStep) {
        guard target != step else { return }
        let reduce = OnboardingTransition.reduceMotion
        direction = target.rawValue > step.rawValue ? 1 : -1
        if direction > 0 { playSound(.advance) }
        sweep = 0
        // One tick later, so the outgoing step has already seen the new direction.
        Task { @MainActor in
            withAnimation(OnboardingTransition.animation(reduceMotion: reduce)) { step = target }
            if let sweepAnimation = OnboardingTransition.sweepAnimation(reduceMotion: reduce) {
                withAnimation(sweepAnimation) { sweep = 1 }
            }
        }
    }

    /// Finishing: the success cue, then the caller closes the window.
    func finish() { playSound(.finish) }

    /// Asleep, then waking, then waving: the mascot's first appearance. Reduce Motion shows it awake.
    func playWake() async {
        guard step == .welcome, !OnboardingTransition.reduceMotion, !TopBarStyle.isSnapshot else { wake = .awake; return }
        wake = .asleep
        do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
        guard step == .welcome, !OnboardingTransition.reduceMotion else { wake = .awake; return }
        wake = .waking
        do { try await Task.sleep(for: .milliseconds(1900)) } catch { return }
        guard step == .welcome else { return }
        wake = .awake
    }
}

/// Root of the 960 x 760 window: watermark, brand, dashes, the step, and the footer.
struct OnboardingRoot: View {
    let flow: OnboardingFlow
    let services: OnboardingServices
    let finish: () -> Void
    @AppStorage("opt.general.windowTheme") private var theme = "System"
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: OB.Palette {
        switch theme {
        case "Light": OB.light
        case "Dark": OB.dark
        default: systemScheme == .light ? OB.light : OB.dark
        }
    }

    var body: some View {
        let reduce = reduceMotion
        ZStack(alignment: .topLeading) {
            palette.canvas
            OnboardingWatermark(shift: OnboardingTransition.watermarkShift(step: flow.step.rawValue, reduceMotion: reduce))
            OnboardingBrand().offset(x: OB.leadingEdge, y: 67.5)
            if flow.step == .welcome {
                Button { cycleTheme() } label: {
                    Image(systemName: "circle.righthalf.filled").font(.system(size: 13)).foregroundStyle(palette.secondary)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: 903.5, y: 68)
                .accessibilityLabel("Window appearance")
                .accessibilityValue(theme)
                .accessibilityHint("Switches between System, Light and Dark.")
            }
            OnboardingProgress(step: flow.step)
                .frame(width: OB.size.width).offset(y: OB.dotsY)

            ZStack {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    if step == flow.step {
                        OnboardingStepView(step: step, flow: flow, services: services)
                            .transition(OnboardingTransition.content(direction: flow.direction, reduceMotion: reduce))
                    }
                }
            }
            .frame(width: OB.size.width, height: OB.size.height)

            if OnboardingLayout.mascotSlot(for: flow.step).isHero { mascot }
            footer
            if !reduce {
                SweepBand(progress: flow.sweep, direction: flow.direction)
                    .frame(width: OB.size.width, height: OB.size.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: OB.size.width, height: OB.size.height)
        .ignoresSafeArea()
        .environment(\.ob, palette)
        .preferredColorScheme(palette.canvas == OB.light.canvas ? .light : .dark)
        .task(id: flow.step) { await flow.playWake() }
    }

    /// The living mascot on the steps that give it a hero slot (welcome and the last step). Slot offsets
    /// are window coordinates, so the frame is top-leading.
    private var mascot: some View {
        let slot = OnboardingLayout.mascotSlot(for: flow.step)
        return ZStack(alignment: .topLeading) {
            MascotTile(pose: flow.mascotPose, side: slot.side)
                .frame(width: slot.side, height: slot.side)
                .offset(x: slot.center.x - slot.side / 2, y: slot.center.y - slot.side / 2)
        }
        .frame(width: OB.size.width, height: OB.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func cycleTheme() {
        theme = switch theme { case "System": "Light"; case "Light": "Dark"; default: "System" }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            if flow.step != .welcome {
                Button { flow.back() } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .medium))
                        Text("Back")
                    }
                }
                .buttonStyle(OBTextButtonStyle())
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .accessibilityLabel("Back")
            }
            Spacer()
            switch flow.step {
            case .welcome:
                Button("Start") { flow.next() }
                    .buttonStyle(OBPrimaryButtonStyle(width: 87))
                    .keyboardShortcut(.defaultAction)
            case .sounds:
                Button("Finish") { flow.finish(); finish() }
                    .buttonStyle(OBPrimaryButtonStyle(width: 93.5))
                    .keyboardShortcut(.defaultAction)
            default:
                Button("Set up later") { flow.next() }
                    .buttonStyle(OBTextButtonStyle())
                    .padding(.trailing, 18.5)
                    .accessibilityHint("Skips this step. You can finish it later in Settings.")
                Button("Continue") { flow.next() }
                    .buttonStyle(OBPrimaryButtonStyle(width: 117.5))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.leading, 33)
        .padding(.trailing, OB.footerRight)
        .frame(width: OB.size.width, height: 44)
        .offset(y: OB.footerButtonTop)
    }
}

/// The guide's window: 960 x 760, centred, traffic lights over a full-size dark canvas.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let flow = OnboardingFlow()
    let services: OnboardingServices
    var onFinish: (() -> Void)?

    init(services: OnboardingServices) {
        self.services = services
    }

    var isVisible: Bool { window?.isVisible == true }
    /// For `zeus debug screenshot --window onboarding`.
    var debugWindow: NSWindow? { window }

    func show(restart: Bool = false) {
        if restart { flow.step = .welcome }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: OB.size),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.title = "Welcome to Zeus"
            window.delegate = self
            let hosting = NSHostingView(rootView: OnboardingRoot(flow: flow, services: services) { [weak self] in self?.finish() })
            hosting.sizingOptions = []
            window.contentView = hosting
            // Glance's frame is 960 x 760 including the title bar (full-size content).
            window.setFrame(NSRect(origin: .zero, size: OB.size), display: false)
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        services.startPolling()
    }

    func windowWillClose(_ notification: Notification) { services.stopPolling() }

    func close() { window?.close() }

    private func finish() {
        UserDefaults.standard.set(true, forKey: OnboardingFlow.completedKey)
        UserDefaults.standard.set(true, forKey: "didOnboard")
        flow.step = .welcome
        window?.close()
        onFinish?()
    }

    /// The window number for screencapture -l (parity captures).
    var windowNumber: Int? { window?.windowNumber }
}

/// `Zeus --onboarding-step 4` opens the guide on that step (1-based), for live parity captures.
@MainActor
enum OnboardingParity {
    /// `Zeus --onboarding-only [--onboarding-step N]`: only the guide (no notch, no menu bar item),
    /// so parity captures never overlap another build's notch.
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--onboarding-only") else { return false }
        NSApp.setActivationPolicy(.accessory)
        let permissions = PermissionsModel()
        let guide = OnboardingWindowController(services: OnboardingServices(permissions: permissions))
        if let step = requestedStep { guide.flow.step = step }
        if let flag = CommandLine.arguments.firstIndex(of: "--onboarding-agent"), flag + 1 < CommandLine.arguments.count {
            guide.flow.agent = CommandLine.arguments[flag + 1] == "claude" ? .claude : .codex
        }
        guide.onFinish = { NSApp.terminate(nil) }
        guide.show()
        keep = guide
        return true
    }

    private static var keep: OnboardingWindowController?

    nonisolated static var requestedStep: OnboardingStep? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--onboarding-step"), flag + 1 < arguments.count,
              let number = Int(arguments[flag + 1]) else { return nil }
        return OnboardingStep(rawValue: number - 1)
    }
}
