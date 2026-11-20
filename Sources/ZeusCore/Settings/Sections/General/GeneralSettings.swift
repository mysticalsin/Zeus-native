import CoreGraphics
import Foundation

/// Window appearance stored in `general.windowTheme`.
/// Dark, glass, and clear glass are the finishes this section offers.
/// System and Light remain readable and resolve to dark.
public enum GeneralWindowAppearance: String, CaseIterable, Sendable {
    case dark = "Dark"
    case glass = "Glass"
    case clearGlass = "Clear glass"

    public static let key = "general.windowTheme"

    public static func resolve(_ stored: String?) -> GeneralWindowAppearance {
        GeneralWindowAppearance(rawValue: stored ?? "") ?? .dark
    }

    public func preview(blur: Double, reduceMotion: Bool, reduceTransparency: Bool) -> GeneralWindowPreview {
        let strength = GeneralBlurStrength.clamp(blur)
        let solid = self == .dark || reduceTransparency
        let opacity: Double
        if solid {
            opacity = 1
        } else {
            switch self {
            case .dark: opacity = 1
            case .glass: opacity = 0.72
            case .clearGlass: opacity = 0.38
            }
        }
        let radius = solid ? 0 : (strength / GeneralBlurStrength.maximum) * 32
        return GeneralWindowPreview(
            appearance: self,
            fillOpacity: opacity,
            blurRadius: radius,
            solid: solid,
            animationDuration: reduceMotion ? 0 : MotionTokens.crossfadeDuration,
            accessibilityLabel: "Window appearance preview, \(rawValue)"
        )
    }
}

public struct GeneralWindowPreview: Equatable, Sendable {
    public var appearance: GeneralWindowAppearance
    public var fillOpacity: Double
    public var blurRadius: Double
    public var solid: Bool
    public var animationDuration: Double
    public var accessibilityLabel: String

    public init(appearance: GeneralWindowAppearance, fillOpacity: Double, blurRadius: Double, solid: Bool, animationDuration: Double, accessibilityLabel: String) {
        self.appearance = appearance
        self.fillOpacity = fillOpacity
        self.blurRadius = blurRadius
        self.solid = solid
        self.animationDuration = animationDuration
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Background blur strength, closed range 0...100 on a step of 1. Missing or non-finite input uses 40.
public enum GeneralBlurStrength {
    public static let key = "general.backgroundBlur"
    public static let minimum = 0.0
    public static let maximum = 100.0
    public static let step = 1.0
    public static let defaultValue = 40.0

    public static func clamp(_ raw: Double) -> Double {
        guard raw.isFinite else { return defaultValue }
        let snapped = (raw / step).rounded() * step
        return min(maximum, max(minimum, snapped))
    }

    public static func parse(_ stored: String?) -> Double {
        guard let stored, let raw = Double(stored) else { return defaultValue }
        return clamp(raw)
    }
}

public enum GeneralDisplayReadout: Equatable, Sendable {
    case loading
    case empty
    case ready([Int])
    case failed(String)
}

/// Which screens show the notch. The choice is `notch.displays`; selection reuses `DisplaySelection`.
public enum GeneralNotchScreens {
    public static let key = "notch.displays"

    public static func mode(_ stored: String?) -> NotchDisplayMode {
        NotchDisplayMode(label: stored ?? "")
    }

    public static func readout(loaded: Bool, screens: [DisplayDescriptor], pointer: CGPoint, mode: NotchDisplayMode, failure: String?) -> GeneralDisplayReadout {
        if let failure {
            let text = failure.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(text.isEmpty ? "Displays could not be read." : text)
        }
        guard loaded else { return .loading }
        guard !screens.isEmpty else { return .empty }
        let ids = DisplaySelection.targets(mode: mode, screens: screens, pointer: pointer).map(\.id)
        return .ready(ids)
    }
}

/// Hide the notch while the front app is full screen. Off unless the stored value is exactly `true`.
public enum GeneralFullScreenHiding {
    public static let key = "general.hideInFullScreen"

    public static func enabled(_ stored: String?) -> Bool { stored == "true" }

    public static func notchVisible(hideWhenFullScreen: Bool, frontmostIsFullScreen: Bool) -> Bool {
        !(hideWhenFullScreen && frontmostIsFullScreen)
    }
}

/// Hide from screen capture. The stored switch is `general.showInScreenSharing`; visibility reuses the shared policy.
public enum GeneralScreenCapture {
    public static let key = ZeusScreenSharePolicy.showInSharingKey

    public static func enabled(_ stored: String?) -> Bool { stored == "true" }

    public static func surfacesVisible(showInScreenSharing: Bool, meetingActive: Bool, teleprompterSessionHidden: Bool) -> Bool {
        ZeusScreenSharePolicy.zeusSurfacesVisible(
            showInScreenSharing: showInScreenSharing,
            meetingActive: meetingActive,
            teleprompterSessionHidden: teleprompterSessionHidden
        )
    }
}

/// Menu bar icon. The stored key is `showMenuBarIcon`, and a missing value stays shown.
public enum GeneralMenuBarIcon {
    public static let key = "showMenuBarIcon"

    public static func shown(_ stored: Bool?) -> Bool { stored ?? true }

    public static func helper(shown: Bool) -> String {
        shown ? "Shows Zeus in the menu bar." : "To get back here, open Zeus again from Applications or Spotlight."
    }
}

/// Width and height stay on Appearance. This section only links there.
public enum GeneralDrawnShapeLink {
    public static let widthKey = "notch.drawnWidth"
    public static let heightKey = "notch.drawnHeight"
    public static let destinationID = "appearance"
    public static let title = "Fit the drawn shape to the notch"
    public static let helper = "Width and height stay on Appearance."
    public static let accessibilityLabel = "Fit the drawn shape to the notch, set in Appearance"
}

public enum GeneralHapticReadout: Equatable, Sendable {
    case loading
    case off
    case on
    case unavailable
    case failed(String)
}

/// Haptic feedback from a Force Touch trackpad. Off by default, and off when the trackpad cannot play it.
public enum GeneralHaptics {
    public static let key = "general.hapticFeedback"

    public static func enabled(_ stored: String?) -> Bool { stored == "true" }

    public static func readout(loaded: Bool, storedOn: Bool, forceTouch: Bool, failure: String?) -> GeneralHapticReadout {
        if storedOn, let failure {
            let text = failure.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(text.isEmpty ? "Haptic feedback is unavailable." : text)
        }
        guard loaded else { return .loading }
        guard storedOn else { return .off }
        guard forceTouch else { return .unavailable }
        return .on
    }

    public static func plays(_ readout: GeneralHapticReadout) -> Bool { readout == .on }
}

/// Launch at login. A missing value follows the catalog default, on. Only `false` and other stored text turn it off.
public enum GeneralLaunchAtLogin {
    public static let key = "general.launchAtLogin"

    public static func enabled(_ stored: String?) -> Bool {
        guard let stored else { return true }
        return stored == "true"
    }
}

/// Run setup again. Starting while a replay is already running does not start a second one.
public enum GeneralSetupReplay: Equatable, Sendable {
    case idle
    case running
    case failed(String)

    public static let key = "general.runSetup"

    public enum Event: Equatable, Sendable {
        case start
        case finished
        case failed(String)
        case dismiss
    }

    public static func transition(_ state: GeneralSetupReplay, _ event: Event) -> GeneralSetupReplay {
        switch (state, event) {
        case (.idle, .start), (.failed, .start):
            return .running
        case (.running, .start):
            return .running
        case (.running, .finished):
            return .idle
        case (.running, .failed(let message)):
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(text.isEmpty ? "The setup guide could not open." : text)
        case (.failed, .dismiss):
            return .idle
        default:
            return state
        }
    }
}

/// Reset every stored setting except the login item and the license. The inputs are not changed.
public enum GeneralSettingsReset {
    public static func preserves(_ key: String) -> Bool {
        bare(key) == GeneralLaunchAtLogin.key || isLicenseKey(key)
    }

    public static func isLicenseKey(_ key: String) -> Bool {
        let key = bare(key)
        return key == "license" || key.hasPrefix("license.")
    }

    public static func applying(values: [String: String], defaults: [String: String]) -> [String: String] {
        var next: [String: String] = [:]
        for (key, value) in defaults where !preserves(key) {
            next[key] = value
        }
        for (key, value) in values where preserves(key) {
            next[key] = value
        }
        for (key, value) in defaults where preserves(key) && values[key] == nil {
            next[key] = value
        }
        return next
    }

    private static func bare(_ key: String) -> String {
        key.hasPrefix("opt.") ? String(key.dropFirst(4)) : key
    }
}

public struct GeneralResetChrome: Equatable, Sendable {
    public var title: String
    public var helper: String
    public var primaryTitle: String?
    public var secondaryTitle: String?
    public var accessibilityLabel: String
    public var showsProgress: Bool
    public var isError: Bool

    public init(title: String, helper: String, primaryTitle: String?, secondaryTitle: String?, accessibilityLabel: String, showsProgress: Bool, isError: Bool) {
        self.title = title
        self.helper = helper
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.accessibilityLabel = accessibilityLabel
        self.showsProgress = showsProgress
        self.isError = isError
    }
}

/// Inline two-step reset. Applying is reachable only from the second confirmation.
public enum GeneralResetConfirmation: Equatable, Sendable {
    case idle
    case review
    case commit
    case applying
    case failed(String)
    case finished

    public enum Event: Equatable, Sendable {
        case ask
        case advance
        case commit
        case cancel
        case succeeded
        case failed(String)
        case dismiss
    }

    public static func transition(_ state: GeneralResetConfirmation, _ event: Event) -> GeneralResetConfirmation {
        switch (state, event) {
        case (.idle, .ask), (.failed, .ask), (.finished, .ask):
            return .review
        case (.review, .advance):
            return .commit
        case (.commit, .commit):
            return .applying
        case (.review, .cancel), (.commit, .cancel):
            return .idle
        case (.applying, .succeeded):
            return .finished
        case (.applying, .failed(let message)):
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(text.isEmpty ? "Settings could not be reset." : text)
        case (.failed, .dismiss), (.finished, .dismiss):
            return .idle
        default:
            return state
        }
    }

    public static func chrome(_ state: GeneralResetConfirmation) -> GeneralResetChrome {
        switch state {
        case .idle:
            return GeneralResetChrome(title: "Reset all settings", helper: "Puts every setting back. Launch at login and the license stay.", primaryTitle: "Reset all settings", secondaryTitle: nil, accessibilityLabel: "Reset all settings", showsProgress: false, isError: false)
        case .review:
            return GeneralResetChrome(title: "Reset all settings?", helper: "Launch at login and the license stay. Everything else returns to its default.", primaryTitle: "Continue", secondaryTitle: "Cancel", accessibilityLabel: "Continue resetting settings", showsProgress: false, isError: false)
        case .commit:
            return GeneralResetChrome(title: "Reset everything else?", helper: "This cannot be undone. Launch at login and the license stay.", primaryTitle: "Reset now", secondaryTitle: "Cancel", accessibilityLabel: "Reset all settings now", showsProgress: false, isError: false)
        case .applying:
            return GeneralResetChrome(title: "Resetting settings", helper: "Resetting settings…", primaryTitle: nil, secondaryTitle: nil, accessibilityLabel: "Resetting settings", showsProgress: true, isError: false)
        case .failed(let message):
            return GeneralResetChrome(title: "Settings were not reset", helper: message, primaryTitle: "Try again", secondaryTitle: "Dismiss", accessibilityLabel: "Settings were not reset. \(message)", showsProgress: false, isError: true)
        case .finished:
            return GeneralResetChrome(title: "Settings reset", helper: "Launch at login and the license are unchanged.", primaryTitle: "Done", secondaryTitle: nil, accessibilityLabel: "Settings reset", showsProgress: false, isError: false)
        }
    }
}

public enum GeneralControlKind: Equatable, Sendable {
    case choice
    case slider
    case toggle
    case link
    case action
}

public enum GeneralControlPlacement: Equatable, Sendable {
    case existingPage
    case card(Int)
    case link(String)
}

public struct GeneralControlSpec: Equatable, Sendable, Identifiable {
    public var id: String
    public var keys: [String]
    public var title: String
    public var helper: String
    public var accessibilityLabel: String
    public var kind: GeneralControlKind
    public var placement: GeneralControlPlacement

    public init(id: String, keys: [String], title: String, helper: String, accessibilityLabel: String, kind: GeneralControlKind, placement: GeneralControlPlacement) {
        self.id = id
        self.keys = keys
        self.title = title
        self.helper = helper
        self.accessibilityLabel = accessibilityLabel
        self.kind = kind
        self.placement = placement
    }
}

public enum GeneralBanner: Equatable, Sendable {
    case loading(String)
    case empty(String)
    case error(String)
}

public enum GeneralSettingsLayout {
    public static let rowHeight = 52.0
    public static let panelPadding = 32.0
    public static let cardSpacing = 28.0
}

public enum GeneralSettingsSectionModel {
    public static let placementSection = "general"
    public static let placementOrder = 1
    public static let previewControlID = "settings.general.windowTheme"

    public static let controls: [GeneralControlSpec] = [
        GeneralControlSpec(id: "settings.general.windowTheme", keys: ["general.windowTheme"], title: "Window appearance", helper: "Dark, glass, or clear glass for Settings.", accessibilityLabel: "Window appearance", kind: .choice, placement: .card(1)),
        GeneralControlSpec(id: "settings.general.backgroundBlur", keys: ["general.backgroundBlur"], title: "Background blur", helper: "0 is no blur and 100 is the strongest.", accessibilityLabel: "Background blur strength", kind: .slider, placement: .card(2)),
        GeneralControlSpec(id: "settings.general.notchDisplays", keys: ["notch.displays"], title: "Show the notch on", helper: "Which screens carry the notch.", accessibilityLabel: "Show the notch on", kind: .choice, placement: .existingPage),
        GeneralControlSpec(id: "settings.general.hideInFullScreen", keys: ["general.hideInFullScreen"], title: "Hide in full-screen apps", helper: "Hides the notch while the front app is full screen.", accessibilityLabel: "Hide in full-screen apps", kind: .toggle, placement: .card(3)),
        GeneralControlSpec(id: "settings.general.showInScreenSharing", keys: ["general.showInScreenSharing"], title: "Show in screen sharing", helper: "Off keeps Zeus windows out of screen shares and recordings.", accessibilityLabel: "Show in screen sharing", kind: .toggle, placement: .existingPage),
        GeneralControlSpec(id: "settings.general.menuBarIcon", keys: ["showMenuBarIcon"], title: "Menu bar icon", helper: "Shows Zeus in the menu bar.", accessibilityLabel: "Menu bar icon", kind: .toggle, placement: .card(4)),
        GeneralControlSpec(id: "settings.general.drawnShape", keys: ["notch.drawnWidth", "notch.drawnHeight"], title: GeneralDrawnShapeLink.title, helper: GeneralDrawnShapeLink.helper, accessibilityLabel: GeneralDrawnShapeLink.accessibilityLabel, kind: .link, placement: .link(GeneralDrawnShapeLink.destinationID)),
        GeneralControlSpec(id: "settings.general.hapticFeedback", keys: ["general.hapticFeedback"], title: "Haptic feedback", helper: "Uses the Force Touch trackpad. Stays off when this Mac has none.", accessibilityLabel: "Haptic feedback", kind: .toggle, placement: .card(5)),
        GeneralControlSpec(id: "settings.general.launchAtLogin", keys: ["general.launchAtLogin"], title: "Launch at login", helper: "Starts Zeus when you log in.", accessibilityLabel: "Launch at login", kind: .toggle, placement: .existingPage),
        GeneralControlSpec(id: "settings.general.runSetup", keys: ["general.runSetup"], title: "Run setup again", helper: "Replays the first-run guide.", accessibilityLabel: "Run setup again", kind: .action, placement: .existingPage),
        GeneralControlSpec(id: "settings.general.reset", keys: [], title: "Reset all settings", helper: "Puts every setting back. Launch at login and the license stay.", accessibilityLabel: "Reset all settings", kind: .action, placement: .card(6)),
    ]

    public static func banner(displays: GeneralDisplayReadout, haptics: GeneralHapticReadout) -> GeneralBanner? {
        if case .failed(let message) = displays { return .error(message) }
        if case .failed(let message) = haptics { return .error(message) }
        if case .loading = displays { return .loading("Loading settings…") }
        if case .loading = haptics { return .loading("Loading settings…") }
        if case .empty = displays { return .empty("No display is connected.") }
        return nil
    }
}

public struct GeneralSettingsInput: Equatable, Sendable {
    public var values: [String: String]
    public var menuBarStored: Bool?
    public var displaysLoaded: Bool
    public var displays: [DisplayDescriptor]
    public var pointer: CGPoint
    public var displayFailure: String?
    public var frontmostIsFullScreen: Bool
    public var meetingActive: Bool
    public var teleprompterSessionHidden: Bool
    public var hapticsLoaded: Bool
    public var forceTouch: Bool
    public var hapticFailure: String?
    public var reduceMotion: Bool
    public var reduceTransparency: Bool

    public init(values: [String: String], menuBarStored: Bool?, displaysLoaded: Bool, displays: [DisplayDescriptor], pointer: CGPoint, displayFailure: String?, frontmostIsFullScreen: Bool, meetingActive: Bool, teleprompterSessionHidden: Bool, hapticsLoaded: Bool, forceTouch: Bool, hapticFailure: String?, reduceMotion: Bool, reduceTransparency: Bool) {
        self.values = values
        self.menuBarStored = menuBarStored
        self.displaysLoaded = displaysLoaded
        self.displays = displays
        self.pointer = pointer
        self.displayFailure = displayFailure
        self.frontmostIsFullScreen = frontmostIsFullScreen
        self.meetingActive = meetingActive
        self.teleprompterSessionHidden = teleprompterSessionHidden
        self.hapticsLoaded = hapticsLoaded
        self.forceTouch = forceTouch
        self.hapticFailure = hapticFailure
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
    }
}

public struct GeneralSettingsOutput: Equatable, Sendable {
    public var appearance: GeneralWindowAppearance
    public var preview: GeneralWindowPreview
    public var blur: Double
    public var displays: GeneralDisplayReadout
    public var notchVisible: Bool
    public var visibleInScreenCapture: Bool
    public var menuBarShown: Bool
    public var menuBarHelper: String
    public var haptics: GeneralHapticReadout
    public var hapticsPlay: Bool
    public var launchAtLogin: Bool
    public var banner: GeneralBanner?

    public init(appearance: GeneralWindowAppearance, preview: GeneralWindowPreview, blur: Double, displays: GeneralDisplayReadout, notchVisible: Bool, visibleInScreenCapture: Bool, menuBarShown: Bool, menuBarHelper: String, haptics: GeneralHapticReadout, hapticsPlay: Bool, launchAtLogin: Bool, banner: GeneralBanner?) {
        self.appearance = appearance
        self.preview = preview
        self.blur = blur
        self.displays = displays
        self.notchVisible = notchVisible
        self.visibleInScreenCapture = visibleInScreenCapture
        self.menuBarShown = menuBarShown
        self.menuBarHelper = menuBarHelper
        self.haptics = haptics
        self.hapticsPlay = hapticsPlay
        self.launchAtLogin = launchAtLogin
        self.banner = banner
    }
}

public enum GeneralSettingsResolver {
    public static func resolve(_ input: GeneralSettingsInput) -> GeneralSettingsOutput {
        let appearance = GeneralWindowAppearance.resolve(input.values[GeneralWindowAppearance.key])
        let blur = GeneralBlurStrength.parse(input.values[GeneralBlurStrength.key])
        let displays = GeneralNotchScreens.readout(
            loaded: input.displaysLoaded,
            screens: input.displays,
            pointer: input.pointer,
            mode: GeneralNotchScreens.mode(input.values[GeneralNotchScreens.key]),
            failure: input.displayFailure
        )
        let hide = GeneralFullScreenHiding.enabled(input.values[GeneralFullScreenHiding.key])
        let sharing = GeneralScreenCapture.enabled(input.values[GeneralScreenCapture.key])
        let haptics = GeneralHaptics.readout(
            loaded: input.hapticsLoaded,
            storedOn: GeneralHaptics.enabled(input.values[GeneralHaptics.key]),
            forceTouch: input.forceTouch,
            failure: input.hapticFailure
        )
        let menuShown = GeneralMenuBarIcon.shown(input.menuBarStored)
        return GeneralSettingsOutput(
            appearance: appearance,
            preview: appearance.preview(blur: blur, reduceMotion: input.reduceMotion, reduceTransparency: input.reduceTransparency),
            blur: blur,
            displays: displays,
            notchVisible: GeneralFullScreenHiding.notchVisible(hideWhenFullScreen: hide, frontmostIsFullScreen: input.frontmostIsFullScreen),
            visibleInScreenCapture: GeneralScreenCapture.surfacesVisible(showInScreenSharing: sharing, meetingActive: input.meetingActive, teleprompterSessionHidden: input.teleprompterSessionHidden),
            menuBarShown: menuShown,
            menuBarHelper: GeneralMenuBarIcon.helper(shown: menuShown),
            haptics: haptics,
            hapticsPlay: GeneralHaptics.plays(haptics),
            launchAtLogin: GeneralLaunchAtLogin.enabled(input.values[GeneralLaunchAtLogin.key]),
            banner: GeneralSettingsSectionModel.banner(displays: displays, haptics: haptics)
        )
    }
}
