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
        var line = "hold \(pushToTalk.title) to talk, double-tap to latch"
        if d.enabled { line += "; dictation: " + (d.key.map { "hold \($0.title)" } ?? "off") }
        return line
    }
}

enum Motion {
    /// System Settings › Accessibility › Display › Reduce motion.
    @MainActor static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Shared interaction timings, all read from the one table in `MotionTokens`. Capture/completion
    /// choreography keeps its own longer sequence.
    static let feedbackDuration = MotionTokens.pressDuration
    static let crossfadeDuration = MotionTokens.crossfadeDuration
    static let pageResponse = MotionTokens.panelResize.response
    static let pageDamping = MotionTokens.panelResize.damping
    static let pressedScale = CGFloat(MotionTokens.pressScale)
    static let windowFadeIn = MotionTokens.windowFadeInDuration
    static let windowFadeOut = MotionTokens.windowFadeOutDuration
    /// Frame rates of clock-driven loops.
    static let ambientFPS = MotionRules.ambientFPS
    static let spinnerFPS = MotionRules.spinnerFPS

    private static func raw(_ token: SpringToken) -> Animation {
        .spring(response: token.response, dampingFraction: token.damping)
    }

    /// A token spring. Under Reduce Motion nothing animates.
    static func spring(_ token: SpringToken, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : raw(token)
    }

    /// A token spring that follows the system's Reduce Motion setting right now.
    @MainActor static func live(_ token: SpringToken) -> Animation? { spring(token, reduceMotion: reduced) }

    /// Any animation, made instant under Reduce Motion.
    static func reducible(_ animation: Animation, reduceMotion: Bool) -> Animation? { reduceMotion ? nil : animation }
    @MainActor static func reducible(_ animation: Animation) -> Animation? { reducible(animation, reduceMotion: reduced) }

    /// The panel closing: no overshoot.
    static let panelClose = raw(MotionTokens.panelClose)
    /// HUD cue wings growing and shrinking.
    static let cueGrow = raw(MotionTokens.cueGrow)
    /// Peek cards arriving beside the closed notch.
    static let peekContent = raw(MotionTokens.peekContent).delay(MotionTokens.peekContentDelay)
    /// A page leaving the panel.
    static let pageOut = Animation.easeOut(duration: MotionTokens.pageOutDuration)

    static func feedback(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: feedbackDuration)
    }

    /// Layout changes settle promptly. Reduced motion changes geometry immediately.
    static func page(reduceMotion: Bool) -> Animation? {
        spring(MotionTokens.panelResize, reduceMotion: reduceMotion)
    }
}
