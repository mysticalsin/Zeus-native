import Foundation

/// Whether this process may honour a path or helper location from the environment.
/// Release builds (`#if !DEBUG`) do not.
public enum SupportOverrideBuild: String, Sendable, Equatable {
    case debug
    case release

    public static var current: SupportOverrideBuild {
        #if !DEBUG
        .release
        #else
        .debug
        #endif
    }
}

/// A read of one environment variable. Tests supply a fixed map. The app supplies the process environment.
public protocol SupportOverrideEnvironment: Sendable {
    func value(_ name: String) -> String?
}

public struct SupportOverrideMap: SupportOverrideEnvironment, Sendable {
    public var values: [String: String]
    public init(_ values: [String: String]) { self.values = values }
    public func value(_ name: String) -> String? { values[name] }
}

public struct ProcessSupportOverrideEnvironment: SupportOverrideEnvironment, Sendable {
    public init() {}
    public func value(_ name: String) -> String? { ProcessInfo.processInfo.environment[name] }
}

/// Zeus path and helper-location overrides. A release build ignores every name here.
public enum SupportOverride {
    public static let names: [String] = [
        "ZEUS_SUPPORT_DIR",
        "ZEUS_SOCKET",
        "ZEUS_LOG_DIR",
        "ZEUS_AGENT_CONFIG_HOME",
        "ZEUS_CLAUDE_SETTINGS",
        "ZEUS_BRAIN_FIXTURE",
        "ZEUS_DEBUG_SCREENSHOT_DIR",
    ]

    /// Non-empty override when this build may use it. Release builds ignore every override.
    /// Empty and whitespace-only values are absent.
    public static func value(_ name: String, environment: some SupportOverrideEnvironment, build: SupportOverrideBuild) -> String? {
        guard build == .debug else { return nil }
        guard let raw = environment.value(name) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The override as this running build sees it.
    public static func resolved(_ name: String, environment: some SupportOverrideEnvironment = ProcessSupportOverrideEnvironment()) -> String? {
        value(name, environment: environment, build: .current)
    }

    public static func supportDirectory(environment: some SupportOverrideEnvironment, build: SupportOverrideBuild, defaultDirectory: String) -> String {
        value("ZEUS_SUPPORT_DIR", environment: environment, build: build) ?? defaultDirectory
    }
}
