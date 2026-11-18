import AppKit
import Observation
import SwiftUI
import ZeusCore

@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    /// "Talk to Zeus": hold to talk, double-tap to latch. Control+Option until you record another
    /// (docs/VOICE-KEY.md). Settings and onboarding set it through `chooseTalkKey`.
    var pushToTalk: Shortcut {
        didSet { defaults.set(Shortcut.stored(pushToTalk), forKey: ShortcutStore.talkKey) }
    }

    /// Shows what ZEUS says as text next to the spark, so nothing is conveyed by sound alone.
    var showCaptions: Bool {
        didSet { defaults.set(showCaptions, forKey: "showCaptions") }
    }

    var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon")
            onMenuBarIconChange?(showMenuBarIcon)
        }
    }

    var onMenuBarIconChange: ((Bool) -> Void)?

    /// Off by default: dates are Gregorian. On follows the Mac's own calendar (e.g. Persian).
    var followSystemCalendar: Bool {
        didSet { defaults.set(followSystemCalendar, forKey: ZeusDates.followSystemKey) }
    }

    static let rightCommandMigration = "hotkeys.rightCommand.v1"

    private init() {
        pushToTalk = ShortcutStore.loadTalk(defaults)
        showCaptions = defaults.object(forKey: "showCaptions") as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        followSystemCalendar = ZeusDates.followsSystem(defaults)
    }
}

extension Preferences {
    /// The owner picked a talk key: saved and marked as a choice, so no later migration moves it.
    func chooseTalkKey(_ shortcut: Shortcut) {
        pushToTalk = shortcut
        ShortcutStore.recordTalkChoice(shortcut, in: defaults)
    }

    /// One line for `zeus status` and hints: what the talk key does right now.
    var talkKeyHint: String {
        let d = DictationSettings.shared
        if d.enabled, d.key == pushToTalk {
            return "double-tap \(pushToTalk.title) to talk, hold it to dictate"
        }
        var line = pushToTalk == .controlOption
            ? "hold \(pushToTalk.title) to talk, let go to send"
            : "hold \(pushToTalk.title) to talk, double-tap to latch"
        if d.enabled { line += "; dictation: " + (d.key.map { "hold \($0.title)" } ?? "off") }
        return line
    }
}

enum Motion {
    /// System Settings › Accessibility › Display › Reduce motion.
    /// Live value: `MotionCenter` republishes `read()` when the system setting changes.
    /// A debug test host may inject reduced motion only after it sets
    /// `ZEUS_MOTION_HARNESS_ACTIVE`. Release builds ignore that variable.
    /// The person's own Reduce Motion setting is never turned off.
    @MainActor static var reduced: Bool { MotionCenter.shared.reduced }

    @MainActor static func read() -> Bool {
        #if DEBUG
        if motionEnvironmentFlag("ZEUS_HARNESS_REDUCE_MOTION") {
            if motionEnvironmentFlag("ZEUS_MOTION_HARNESS_ACTIVE") {
                return true
            }
            if !MotionHarnessWarning.shared.warned {
                MotionHarnessWarning.shared.warned = true
                FileHandle.standardError.write(Data("ZEUS_HARNESS_REDUCE_MOTION is ignored outside the test host\n".utf8))
            }
        }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Shared interaction timings. Capture/completion choreography keeps its own longer sequence.
    static let feedbackDuration = 0.12
    static let crossfadeDuration = 0.12
    static let pageResponse = 0.34
    static let pageDamping = 0.84
    static let pressedScale: CGFloat = 0.98

    static func feedback(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: feedbackDuration)
    }

    /// Layout changes settle promptly. Reduced motion changes geometry immediately.
    static func page(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: pageResponse, dampingFraction: pageDamping)
    }
}

#if DEBUG
@MainActor
private final class MotionHarnessWarning {
    static let shared = MotionHarnessWarning()
    var warned = false
}

private func motionEnvironmentFlag(_ name: String) -> Bool {
    guard let value = getenv(name) else { return false }
    return String(cString: value) == "1"
}
#endif

/// One observable Reduce Motion value for SwiftUI. Updated from `Motion.read()` when the
/// system accessibility display options change, so views keep tracking the person's setting.
@MainActor
@Observable
final class MotionCenter {
    static let shared = MotionCenter()
    private(set) var reduced: Bool
    private var token: NSObjectProtocol?

    private init() {
        reduced = Motion.read()
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { MotionCenter.shared.refresh() }
        }
    }

    func refresh() {
        reduced = Motion.read()
    }

    /// Test seam. Sets the published value without touching System Settings,
    /// `com.apple.universalaccess`, or `defaults`. Production code never calls it.
    #if DEBUG
    func testingSetReduced(_ value: Bool) {
        reduced = value
    }
    #endif
}

/// A body that reads `Motion.reduced` publishes the value it applied.
/// The macOS live-update test reads this after flipping `MotionCenter`.
struct MotionLiveSampleKey: PreferenceKey {
    static let defaultValue: Bool? = nil
    static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
        value = nextValue() ?? value
    }
}

/// Press scale and the animation that follows it. `body` reads `Motion.reduced`,
/// so SwiftUI updates this when that setting changes. Button and toggle styles
/// apply it from `makeBody` and do not read `Motion.reduced` themselves.
struct MotionEffect: ViewModifier {
    enum Curve { case feedback, page }

    /// Pressed, or a toggle's isOn. The animation tracks this value.
    var active: Bool
    var enabled: Bool = true
    /// Uses `Motion.pressedScale` only while active, enabled, and motion is allowed.
    var presses: Bool = false
    var curve: Curve = .feedback
    /// Replaces the system value when set, including `false` (`PressableStyle`'s override).
    var forced: Bool? = nil
    /// Onboarding fixtures may add reduction. They cannot turn the person's setting off.
    var includesOnboardingOverride: Bool = false

    @Environment(\.onboardingReduceMotion) private var onboardingOverride

    func body(content: Content) -> some View {
        let reduced = resolved
        content
            .scaleEffect(presses && active && enabled && !reduced ? Motion.pressedScale : 1)
            .animation(animation(reduced), value: active)
            .preference(key: MotionLiveSampleKey.self, value: reduced)
    }

    private var resolved: Bool {
        if let forced { return forced }
        let system = Motion.reduced
        guard includesOnboardingOverride else { return system }
        return OnboardingMotionPolicy.reduced(system: system, override: onboardingOverride)
    }

    private func animation(_ reduced: Bool) -> Animation? {
        switch curve {
        case .feedback: Motion.feedback(reduceMotion: reduced)
        case .page: Motion.page(reduceMotion: reduced)
        }
    }
}
