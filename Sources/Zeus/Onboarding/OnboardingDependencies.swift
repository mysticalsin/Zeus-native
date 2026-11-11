import AppKit
import Observation
import SwiftUI
import ZeusCore

/// SwiftUI's accessibilityReduceMotion is read-only. This guide-owned override makes isolated
/// fixtures deterministic while production still reads the real accessibility preference.
private struct OnboardingMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var onboardingReduceMotion: Bool? {
        get { self[OnboardingMotionOverrideKey.self] }
        set { self[OnboardingMotionOverrideKey.self] = newValue }
    }
}

enum OnboardingMotionPolicy {
    /// An explicit fixture policy may reduce motion further, never override the person's preference.
    static func reduced(system: Bool, override: Bool?) -> Bool { system || (override ?? false) }
}

/// Only the capabilities presented by the welcome guide. Implementations own all effects.
enum OnboardingCapability: String, CaseIterable, Sendable {
    case microphone, accessibility, notifications, fullDiskAccess, automation, location, calendar, reminders
}

enum OnboardingAccess: Equatable, Sendable {
    case notGranted, denied, allowed

    var recovery: String? {
        self == .denied ? "Not allowed. Open System Settings, or set up later." : nil
    }

    var actionTitle: String? {
        switch self {
        case .allowed: nil
        case .denied: "Open Settings"
        case .notGranted: "Allow"
        }
    }

}

/// A fixture can present every step without constructing any live permission or provider service.
@MainActor
protocol OnboardingServing: AnyObject {
    func access(_ capability: OnboardingCapability) -> OnboardingAccess
    func request(_ capability: OnboardingCapability)
    var modelReady: Bool { get }
    var modelProgress: Double? { get }
    var modelProblem: String? { get }
    func downloadModel()
    var connectMessage: String? { get }
    var automationMessage: String? { get }
    func connect(_ agent: OnboardingFlow.AgentChoice)
    func isConnected(_ agent: OnboardingFlow.AgentChoice) -> Bool
    func refresh()
    func startPolling()
    func stopPolling()
}

/// Persistence and feedback are explicit; creating an inert fixture never reads user defaults.
@MainActor
struct OnboardingPersistence {
    var readStep: () -> Int
    var writeStep: (Int) -> Void
    var readCompleted: () -> Bool
    var markCompleted: () -> Void
    /// Whether the person closed the guide before finishing (defaults keep older fixtures valid).
    var readDismissed: () -> Bool = { false }
    var markDismissed: () -> Void = {}

    static var live: Self {
        Self(readStep: { UserDefaults.standard.integer(forKey: OnboardingFlow.stepKey) },
             writeStep: { if !TopBarStyle.isSnapshot { UserDefaults.standard.set($0, forKey: OnboardingFlow.stepKey) } },
             readCompleted: { OnboardingFlow.isCompleted },
             markCompleted: {
                 guard !TopBarStyle.isSnapshot else { return }
                 UserDefaults.standard.set(true, forKey: OnboardingFlow.completedKey)
                 UserDefaults.standard.set(true, forKey: "didOnboard")
             },
             readDismissed: { OnboardingFlow.isDismissed },
             markDismissed: {
                 guard !TopBarStyle.isSnapshot else { return }
                 UserDefaults.standard.set(true, forKey: OnboardingFlow.dismissedKey)
             })
    }
}

@MainActor
struct OnboardingFeedback {
    var reduceMotion: () -> Bool
    var isSnapshot: () -> Bool
    var playSound: (OnboardingSound) -> Void

    static var live: Self {
        Self(reduceMotion: { OnboardingTransition.reduceMotion }, isSnapshot: { TopBarStyle.isSnapshot }, playSound: { $0.play() })
    }
}

/// Guide-owned preferences. Live access delegates to the same stores as Settings; fixture access
/// is a value dictionary and a supplied preview action, with no live-store construction.
@MainActor @Observable
final class OnboardingOptions {
    struct Access {
        var read: (String) -> String
        var write: (String, String) -> Void
        var talkKey: () -> String
        var preview: (ZeusSound.Event) -> Void
    }

    @ObservationIgnored private let access: Access?
    private var values: [String: String]
    private let fixtureTalkKey: String
    @ObservationIgnored private let fixturePreview: (ZeusSound.Event) -> Void
    // Invalidates computed reads after writes, including the live window-theme defaults value.
    private var revision = 0
    var haloDrawn = 1.0

    init(values: [String: String] = [:], talkKey: String = "⌥ Space", preview: @escaping (ZeusSound.Event) -> Void = { _ in }) {
        access = nil
        self.values = values
        fixtureTalkKey = talkKey
        fixturePreview = preview
    }

    private init(access: Access) {
        self.access = access
        values = [:]
        fixtureTalkKey = ""
        fixturePreview = { _ in }
    }

    static var live: OnboardingOptions {
        OnboardingOptions(access: Access(read: { key in
            switch key {
            case "general.windowTheme": UserDefaults.standard.string(forKey: "opt.general.windowTheme") ?? "System"
            case "notify.approvals": String(ExtraPreferences.shared.peekApprovals)
            case "notify.agentDone": String(ExtraPreferences.shared.peekAgentDone)
            case "sound.on": String(ExtraPreferences.shared.soundsOn)
            default: SettingsStore.shared.string(key)
            }
        }, write: { key, value in
            switch key {
            case "general.windowTheme": if !TopBarStyle.isSnapshot { UserDefaults.standard.set(value, forKey: "opt.general.windowTheme") }
            case "notify.approvals": ExtraPreferences.shared.peekApprovals = value == "true"
            case "notify.agentDone": ExtraPreferences.shared.peekAgentDone = value == "true"
            case "sound.on": ExtraPreferences.shared.soundsOn = value == "true"
            default: SettingsStore.shared.set(key, value)
            }
        }, talkKey: { Preferences.shared.pushToTalk.title }, preview: { SoundStyles.preview($0) }))
    }

    var talkKey: String { access?.talkKey() ?? fixtureTalkKey }

    func refreshExternalPreferences() {
        guard access != nil else { return }
        revision += 1
    }

    func string(_ key: String) -> String {
        _ = revision
        if let access { return access.read(key) }
        return values[key] ?? Self.defaults[key] ?? ""
    }
    func bool(_ key: String) -> Bool { string(key) == "true" }
    func double(_ key: String) -> Double {
        guard let value = Double(string(key)), value.isFinite else { return 0 }
        return min(max(value, -1_000_000_000), 1_000_000_000)
    }
    func set(_ key: String, _ value: String) {
        guard string(key) != value else { return }
        if let access { access.write(key, value) } else { values[key] = value }
        revision += 1
    }
    func binding(_ key: String) -> Binding<String> { Binding(get: { self.string(key) }, set: { self.set(key, $0) }) }
    func boolBinding(_ key: String) -> Binding<Bool> { Binding(get: { self.bool(key) }, set: { self.set(key, String($0)) }) }
    var haloStyleTitle: Binding<String> {
        Binding(get: { HaloStyle.resolve(self.string("halo.style")).title },
                set: { self.set("halo.style", HaloStyle.resolve($0).rawValue) })
    }
    var haloEntranceTitle: Binding<String> {
        Binding(get: { HaloEntrance.resolve(self.string("halo.entrance")).title },
                set: { self.set("halo.entrance", HaloEntrance.resolve($0).rawValue) })
    }
    func preview(_ event: ZeusSound.Event) {
        guard bool("sound.on") else { return }
        if let access { access.preview(event) } else { fixturePreview(event) }
    }

    // The guide's initial fixture values; no SettingsStore initializer or migration runs here.
    private static let defaults = [
        "general.windowTheme": "System", "notify.approvals": "true", "notify.agentDone": "true", "notify.errors": "true",
        "notch.displays": "Built-in display", "insomnia.lidClosed": "false", "appearance.cardStyle": "Liquid Glass",
        "halo.style": "classic", "halo.entrance": "sweep", "halo.armWidth": "Medium", "halo.thickness": "100",
        "sound.on": "true", "sound.startStyle": "Classic", "sound.approvalStyle": "Classic",
        "sound.answerStyle": "Classic", "sound.doneStyle": "Success",
    ]
}
