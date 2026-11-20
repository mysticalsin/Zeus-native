import Foundation

public struct BatteryPreferences: Equatable, Sendable {
    public var lightsEnabled: Bool
    public var style: BatteryOverlayStyle
    public var earbudsEnabled: Bool

    public init(lightsEnabled: Bool, style: BatteryOverlayStyle, earbudsEnabled: Bool) {
        self.lightsEnabled = lightsEnabled
        self.style = style
        self.earbudsEnabled = earbudsEnabled
    }

    public static let standard = BatteryPreferences(lightsEnabled: BatteryLightsSetting.defaultEnabled, style: .gauge, earbudsEnabled: BatteryEarbudSetting.defaultEnabled)
}

public enum BatteryPowerObservation: Equatable, Sendable {
    case loading
    case failed
    case noBattery
    case battery(BatteryPowerSample)
}

public enum BatteryPreviewLoad: Equatable, Sendable {
    case loading
    case empty
    case failed(String)
    case ready
}

public struct BatteryPreviewPart: Equatable, Sendable {
    public var title: String
    public var text: String
    public var accessibilityLabel: String

    public init(title: String, text: String, accessibilityLabel: String) {
        self.title = title
        self.text = text
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct BatteryPreviewModel: Equatable, Sendable {
    public var load: BatteryPreviewLoad
    public var ringFraction: Double?
    public var ringLabel: String
    public var charging: Bool
    public var style: BatteryOverlayStyle
    public var earbuds: [BatteryPreviewPart]
    public var modeLabel: String?
    public var animationDuration: TimeInterval
    public var reduceMotion: Bool

    public init(load: BatteryPreviewLoad, ringFraction: Double?, ringLabel: String, charging: Bool, style: BatteryOverlayStyle, earbuds: [BatteryPreviewPart], modeLabel: String?, animationDuration: TimeInterval, reduceMotion: Bool) {
        self.load = load
        self.ringFraction = ringFraction
        self.ringLabel = ringLabel
        self.charging = charging
        self.style = style
        self.earbuds = earbuds
        self.modeLabel = modeLabel
        self.animationDuration = animationDuration
        self.reduceMotion = reduceMotion
    }
}

public enum BatteryPreview {
    public static func make(observation: BatteryPowerObservation, preferences: BatteryPreferences, earbud: EarbudStatusReport?, reduceMotion: Bool) -> BatteryPreviewModel {
        let earbuds = parts(preferences: preferences, report: earbud)
        let mode = preferences.earbudsEnabled ? modeLabel(earbud?.mode) : nil
        let duration = BatteryMotion.duration(reduceMotion: reduceMotion, style: preferences.style)
        switch observation {
        case .loading:
            return model(.loading, fraction: nil, label: BatterySectionCopy.loadingLabel, charging: false, preferences: preferences, earbuds: earbuds, mode: mode, duration: duration, reduceMotion: reduceMotion)
        case .noBattery:
            return model(.empty, fraction: nil, label: BatterySectionCopy.emptyTitle, charging: false, preferences: preferences, earbuds: earbuds, mode: mode, duration: duration, reduceMotion: reduceMotion)
        case .failed:
            return model(.failed(BatterySectionCopy.errorTitle), fraction: nil, label: BatterySectionCopy.errorTitle, charging: false, preferences: preferences, earbuds: earbuds, mode: mode, duration: duration, reduceMotion: reduceMotion)
        case .battery(let sample):
            guard let percent = sample.percent, (0...100).contains(percent) else {
                return model(.failed(BatterySectionCopy.errorTitle), fraction: nil, label: BatterySectionCopy.errorTitle, charging: false, preferences: preferences, earbuds: earbuds, mode: mode, duration: duration, reduceMotion: reduceMotion)
            }
            let word = sample.charging ? "charging" : "on battery"
            return model(.ready, fraction: Double(percent) / 100, label: "Battery \(percent) percent, \(word)", charging: sample.charging, preferences: preferences, earbuds: earbuds, mode: mode, duration: duration, reduceMotion: reduceMotion)
        }
    }

    private static func parts(preferences: BatteryPreferences, report: EarbudStatusReport?) -> [BatteryPreviewPart] {
        if !preferences.earbudsEnabled {
            return [.left, .right, .cradle].map { unknown($0) }
        }
        guard let report else { return [.left, .right, .cradle].map { unknown($0) } }
        return report.visibleParts.map { part in
            let text = EarbudLevelText.display(report.levels[part] ?? .unknown)
            return BatteryPreviewPart(title: part.title, text: text, accessibilityLabel: "\(part.title) battery \(spoken(text))")
        }
    }

    private static func unknown(_ part: EarbudPart) -> BatteryPreviewPart {
        BatteryPreviewPart(title: part.title, text: "unknown", accessibilityLabel: "\(part.title) battery unknown")
    }

    private static func spoken(_ text: String) -> String {
        text == "unknown" ? "unknown" : text
    }

    private static func modeLabel(_ row: ListeningModeRow?) -> String? {
        guard case .shown(let current, _) = row else { return nil }
        return current.title
    }

    private static func model(_ load: BatteryPreviewLoad, fraction: Double?, label: String, charging: Bool, preferences: BatteryPreferences, earbuds: [BatteryPreviewPart], mode: String?, duration: TimeInterval, reduceMotion: Bool) -> BatteryPreviewModel {
        BatteryPreviewModel(load: load, ringFraction: fraction, ringLabel: label, charging: charging, style: preferences.style, earbuds: earbuds, modeLabel: mode, animationDuration: duration, reduceMotion: reduceMotion)
    }
}

public struct BatteryControlCopy: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var helper: String
    public var accessibilityLabel: String

    public init(id: String, title: String, helper: String, accessibilityLabel: String) {
        self.id = id
        self.title = title
        self.helper = helper
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum BatterySectionCopy {
    public static let title = "Battery"
    public static let previewTitle = "Preview"
    public static let previewHelper = "A live charge ring. Earbud levels stay unknown while the setting is off."
    public static let loadingLabel = "Loading battery"
    public static let emptyTitle = "No internal battery"
    public static let emptyHelper = "This Mac reports no internal battery."
    public static let errorTitle = "Battery status unavailable"

    public static let controls: [BatteryControlCopy] = [
        BatteryControlCopy(
            id: BatteryLightsSetting.key,
            title: "Show the battery level when power changes",
            helper: "On when a charger connects or the charge is low. Off leaves the notch quiet.",
            accessibilityLabel: "Show the battery level when power changes"
        ),
        BatteryControlCopy(
            id: BatteryOverlayStyle.storageKey,
            title: "Overlay style",
            helper: "Gauge follows the notch outline. Ring draws a charge ring. Readout shows the percent.",
            accessibilityLabel: "Overlay style"
        ),
        BatteryControlCopy(
            id: BatteryEarbudSetting.key,
            title: "Earbud battery and listening mode",
            helper: "Off until you turn it on. Zeus asks for Bluetooth only then, and shows unknown when a level is missing.",
            accessibilityLabel: "Earbud battery and listening mode"
        ),
    ]
}

public enum BatterySectionAccessibility {
    public static let focusOrder: [String] = BatterySectionCopy.controls.map(\.id) + ["battery.preview"]
}

public enum BatterySectionMetrics {
    public static let rowHeight = 52.0
    public static let panelPadding = 32.0
    public static let cardGap = 28.0
}

public enum BatterySectionPlacement {
    /// Third tab on the Topbar page, once that placement API is available.
    public static let topbarTab = 3
}
