/// Resolves the explicit settings-harness launch flag before normal app services start.
/// A release build refuses the flag instead of falling through into the full application.
public enum ZeusStartupMode: Equatable, Sendable {
    case normal
    case jevSettingsTest
    case unsupportedJevSettingsTest

    /// The only mode permitted to continue into AppDelegate and its normal background services.
    public var allowsFullAppStartup: Bool { self == .normal }

    public static func resolve(arguments: [String], isDebugBuild: Bool) -> ZeusStartupMode {
        guard arguments.contains("--jev-settings-test") else { return .normal }
        return isDebugBuild ? .jevSettingsTest : .unsupportedJevSettingsTest
    }
}
