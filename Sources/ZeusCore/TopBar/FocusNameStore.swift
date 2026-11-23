import Foundation

public enum FocusNameStatus: Equatable, Sendable {
    case off
    case needsFullDiskAccess
    case unavailable
    case named(String)
}

/// The active Focus name from the local Do Not Disturb store. The bytes are bounded and the
/// files are only interpreted as the mode-name and assertion records this reader understands.
public enum FocusNameStore {
    public static let settingID = "music.focusName"
    public static let maxBytes = 65_536

    public struct Files: Equatable, Sendable {
        public var configurations: Data?
        public var assertions: Data?
        public var permissionDenied: Bool

        public init(configurations: Data?, assertions: Data?, permissionDenied: Bool) {
            self.configurations = configurations
            self.assertions = assertions
            self.permissionDenied = permissionDenied
        }
    }

    public static func status(enabled: Bool, files: Files) -> FocusNameStatus {
        guard enabled else { return .off }
        if files.permissionDenied { return .needsFullDiskAccess }
        guard let configurations = files.configurations, let assertions = files.assertions,
              configurations.count <= maxBytes, assertions.count <= maxBytes,
              let name = activeName(configurations: configurations, assertions: assertions) else { return .unavailable }
        return .named(name)
    }

    public static func activeName(configurations: Data, assertions: Data) -> String? {
        guard configurations.count <= maxBytes, assertions.count <= maxBytes,
              let config = try? JSONSerialization.jsonObject(with: configurations),
              let asserted = try? JSONSerialization.jsonObject(with: assertions) else { return nil }
        var names: [String: String] = [:]
        collectNames(config, into: &names, depth: 0)
        var active: String?
        collectActive(asserted, into: &active, depth: 0)
        guard let active, let name = names[active] else { return nil }
        return FocusNameReader.parse(name)
    }

    private static func collectNames(_ value: Any, into names: inout [String: String], depth: Int) {
        guard depth < 8 else { return }
        if let list = value as? [Any] {
            for item in list { collectNames(item, into: &names, depth: depth + 1) }
            return
        }
        guard let dict = value as? [String: Any] else { return }
        if let id = dict["modeIdentifier"] as? String,
           let mode = dict["mode"] as? [String: Any],
           let name = mode["name"] as? String {
            names[id] = name
        }
        for child in dict.values { collectNames(child, into: &names, depth: depth + 1) }
    }

    private static func collectActive(_ value: Any, into active: inout String?, depth: Int) {
        guard active == nil, depth < 8 else { return }
        if let list = value as? [Any] {
            for item in list { collectActive(item, into: &active, depth: depth + 1) }
            return
        }
        guard let dict = value as? [String: Any] else { return }
        if let id = dict["assertionDetailsModeIdentifier"] as? String, !id.isEmpty {
            active = id
            return
        }
        for child in dict.values { collectActive(child, into: &active, depth: depth + 1) }
    }
}
