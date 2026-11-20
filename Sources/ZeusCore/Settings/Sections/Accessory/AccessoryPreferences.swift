import Foundation

public enum AccessoryPreferenceKey {
    public static let earbudsOverlay = "accessory.earbudsOverlay"
    public static let overlayStyle = "accessory.overlayStyle"
    public static let speakerNames = "accessory.speakerNames"
}

public enum AccessoryOverlayStyle: String, Codable, CaseIterable, Sendable, Equatable {
    case off
    case compact
    case split

    public static func resolved(_ raw: String?) -> AccessoryOverlayStyle {
        guard let raw, let style = AccessoryOverlayStyle(rawValue: raw) else { return .off }
        return style
    }
}

public enum AccessoryPlacement: Equatable, Sendable {
    case topbarTab(Int)
}

public struct AccessoryPreferences: Equatable, Sendable, Codable {
    public var earbudsOverlay: Bool
    public var overlayStyle: AccessoryOverlayStyle
    public var speakerNames: Bool

    public init(earbudsOverlay: Bool, overlayStyle: AccessoryOverlayStyle, speakerNames: Bool) {
        self.earbudsOverlay = earbudsOverlay
        self.overlayStyle = overlayStyle
        self.speakerNames = speakerNames
    }

    public static let failClosed = AccessoryPreferences(earbudsOverlay: false, overlayStyle: .off, speakerNames: false)

    public static func restored(overlay: String?, style: String?, speakers: String?) -> AccessoryPreferences {
        AccessoryPreferences(
            earbudsOverlay: overlay == "true",
            overlayStyle: AccessoryOverlayStyle.resolved(style),
            speakerNames: speakers == "true"
        )
    }

    /// An imported file can leave a choice alone or turn it off. It cannot turn one on.
    public func applyingImport(_ imported: AccessoryPreferences) -> AccessoryPreferences {
        AccessoryPreferences(
            earbudsOverlay: earbudsOverlay && imported.earbudsOverlay,
            overlayStyle: overlayStyle == .off ? .off : imported.overlayStyle,
            speakerNames: speakerNames && imported.speakerNames
        )
    }
}

public enum AccessoryLayoutMetrics {
    public static let rowHeight = 52.0
    public static let panelPadding = 32.0
    public static let cardSpacing = 28.0
}

public struct AccessoryControlCopy: Equatable, Sendable {
    public var title: String
    public var helper: String
    public var accessibilityLabel: String
    public var accessibilityHint: String

    public init(title: String, helper: String, accessibilityLabel: String, accessibilityHint: String) {
        self.title = title
        self.helper = helper
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
    }
}

public enum AccessoryCopy {
    public static let earbuds = AccessoryControlCopy(
        title: "Overlay when earbuds connect",
        helper: "Shows a small overlay when earbuds connect. Off until you turn it on.",
        accessibilityLabel: "Overlay when earbuds connect",
        accessibilityHint: "Shows a small overlay when earbuds connect. Off until you turn it on."
    )
    public static let style = AccessoryControlCopy(
        title: "Overlay style",
        helper: "Off shows nothing. Compact is one line. Split shows each side.",
        accessibilityLabel: "Overlay style",
        accessibilityHint: "Off shows nothing. Compact is one line. Split shows each side."
    )
    public static let speakers = AccessoryControlCopy(
        title: "Nearby speaker names",
        helper: "Shows speakers on your local network. Off until you turn it on. Permission is asked only after you confirm.",
        accessibilityLabel: "Nearby speaker names",
        accessibilityHint: "Shows speakers on your local network. Off until you turn it on. Permission is asked only after you confirm."
    )
    public static let enableConfirmation = "Look for speakers on your local network? Permission is asked only after you confirm. Nothing is searched until then."
    public static let confirm = "Look"
    public static let cancel = "Not now"
    public static let previewOff = "Overlay preview is off."

    public static func styleChoice(_ style: AccessoryOverlayStyle) -> String {
        switch style {
        case .off: "Off"
        case .compact: "Compact"
        case .split: "Split"
        }
    }
}
