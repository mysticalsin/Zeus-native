import Foundation

/// The owner's opt-in for face approval. It lives in the settings catalog as `face.approval`.
public enum FaceApprovalPreference {
    public static let key = "face.approval"
    public static let storedDefault = "false"
    public static let contribution = SettingsKeyContribution(
        id: key, defaultValue: storedDefault, kind: .toggle, policy: .importCannotEnable
    )

    public static func isOn(_ stored: String?) -> Bool { stored == "true" }

    /// Settings text only. Sample numbers passed in are ignored so they cannot leak into an export.
    public static func exportDocument(settings: [String: String], samples: [[Float]]) -> String {
        _ = samples
        return settings.keys.sorted().map { "\($0)=\(settings[$0] ?? "")" }.joined(separator: "\n")
    }
}

/// A stand-in for the settings dictionary. Recreating it from `values` is a relaunch.
public struct FaceApprovalMemory: Equatable, Sendable {
    public private(set) var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public var isOn: Bool { FaceApprovalPreference.isOn(values[FaceApprovalPreference.key]) }

    public mutating func setOn(_ on: Bool) {
        values[FaceApprovalPreference.key] = on ? "true" : "false"
    }

    public func recreated() -> FaceApprovalMemory {
        FaceApprovalMemory(values: values)
    }

    /// A file may turn the switch off. It may not turn it on. Other rows are copied.
    public mutating func importFile(_ options: [String: String]) {
        for (id, value) in options {
            if id == FaceApprovalPreference.key {
                if value == "false" { values[id] = "false" }
                continue
            }
            values[id] = value
        }
    }
}
