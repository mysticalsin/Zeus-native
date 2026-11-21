import Foundation

/// Keys for the Focus section. Existing keys stay as they are. Every new key is off until the owner turns it on.
public enum FocusSettingKey {
    public static let transitionOverlay = "focus.transitionOverlay"
    public static let overlaysAllowed = "focus.overlaysAllowed"
    public static let lockScreen = "focus.lockScreen"
    public static let readName = "focus.name.read"
    public static let storeFile = "focus.name.storeFile"
    public static let localNetwork = "focus.name.localNetwork"
    public static let sharedLink = "focus.name.sharedLink"
    public static let homeWidget = "home.widget.2"

    public static let optIn = [
        transitionOverlay, overlaysAllowed, lockScreen, readName, storeFile, localNetwork, sharedLink,
    ]

    /// An imported settings file may turn these off. It cannot turn them on.
    public static let sensitive = optIn
}

/// The Focus section's stored choices. New choices start off and an imported file cannot turn them on.
public struct FocusSectionSettings: Equatable, Sendable {
    public var transitionOverlay = false
    public var overlaysAllowed = false
    public var lockScreen = false
    public var readName = false
    public var storeFile = false
    public var localNetwork = false
    public var sharedLink = false
    public var homeWidget: String? = "Focus"

    public init() {}

    public static let closed = FocusSectionSettings()

    /// A settings file can change the home widget. It cannot turn a Focus feature on.
    public static func imported(bools: [String: Bool], homeWidget: String?) -> FocusSectionSettings {
        var settings = FocusSectionSettings()
        settings.homeWidget = homeWidget
        if FocusSettingKey.optIn.contains(where: { bools[$0] == true }) {
            settings.transitionOverlay = false
            settings.overlaysAllowed = false
            settings.lockScreen = false
            settings.readName = false
            settings.storeFile = false
            settings.localNetwork = false
            settings.sharedLink = false
        }
        return settings
    }
}

public enum FocusPermission: String, Equatable, Sendable {
    case focusStatus
    case fullDisk
    case localNetwork
}

public enum FocusPermissionAnswer: Equatable, Sendable {
    case notDetermined
    case allowed
    case denied
}

/// What Zeus knows about the current Focus. `unknown` is not treated as on or off.
public enum FocusActivity: Equatable, Sendable {
    case unknown
    case off
    case on(name: String?)

    public var isOn: Bool {
        if case .on = self { return true }
        return false
    }
}

public enum FocusRowStatus: Equatable, Sendable {
    case off
    case checking
    case allowed
    case unavailable(String)
}

