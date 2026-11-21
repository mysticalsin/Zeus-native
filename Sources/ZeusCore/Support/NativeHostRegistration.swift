import Foundation

/// What to do with Zeus's own native-messaging host file after a bridge signature check.
/// Other host files in the same directory are never named here.
public enum NativeHostRegistration {
    public static let zeusHostFileName = "com.zeus.bridge.json"

    public enum Action: Equatable, Sendable {
        case keep
        case remove
    }

    /// A refusal currently leaves the registration in place. The file stays.
    public static func action(
        decision: BundledHelperLaunchDecision,
        checkedPath: String,
        manifestFileName: String,
        manifestExecutablePath: String?
    ) -> Action {
        _ = (decision, checkedPath, manifestFileName, manifestExecutablePath)
        return .keep
    }

    /// Deletes `com.zeus.bridge.json` when the action is remove. No other file name is removed.
    public static func apply(action: Action, in directory: URL) throws {
        guard action == .remove else { return }
        let url = directory.appendingPathComponent(zeusHostFileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Reads the `path` in Zeus's own host file and applies `action`. Other files stay.
    public static func reconcile(decision: BundledHelperLaunchDecision, checkedPath: String, hostsDirectory: URL) throws {
        let file = hostsDirectory.appendingPathComponent(zeusHostFileName)
        let named = executablePath(in: file)
        let chosen = action(decision: decision, checkedPath: checkedPath, manifestFileName: zeusHostFileName, manifestExecutablePath: named)
        try apply(action: chosen, in: hostsDirectory)
    }

    private static func executablePath(in file: URL) -> String? {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["path"] as? String
    }
}
