import Foundation

/// What to do with Zeus's own native-messaging host file after a bridge signature check.
/// Other host files in the same directory are never named here.
public enum NativeHostRegistration {
    public static let zeusHostFileName = "com.zeus.bridge.json"

    public enum Action: Equatable, Sendable {
        case keep
        case remove
    }

    public enum Outcome: Equatable, Sendable {
        case kept
        case removed
        case removalFailed
    }

    /// Fixed text for the private logger. It names no path.
    public static let removalFailedMessage = "could not remove the refused host registration"

    /// Remove Zeus's own host file when a refusal's registration names the path that failed
    /// or a user-writable `zeus-bridge` copy. A passing check keeps the file. Any other file name stays.
    public static func action(
        decision: BundledHelperLaunchDecision,
        checkedPath: String,
        manifestFileName: String,
        manifestExecutablePath: String?
    ) -> Action {
        guard manifestFileName == zeusHostFileName else { return .keep }
        guard case .refuse = decision else { return .keep }
        guard let named = manifestExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines), !named.isEmpty else { return .keep }
        let refused = checkedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if named == refused { return .remove }
        if BundledHelperLaunchPolicy.isUserWritableHelperCopy(named),
           BundledHelperLaunchPolicy.signingIdentifier(forExecutablePath: named) == BundledHelperLaunchPolicy.bridgeSigningIdentifier {
            return .remove
        }
        return .keep
    }

    /// Deletes `com.zeus.bridge.json` when the action is remove. No other file name is removed.
    /// A delete error is reported as success until the caller handles it.
    public static func apply(action: Action, in directory: URL, remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) -> Outcome {
        guard action == .remove else { return .kept }
        let url = directory.appendingPathComponent(zeusHostFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return .removed }
        do {
            try remove(url)
            return .removed
        } catch {
            return .removed
        }
    }

    /// Reads the `path` in Zeus's own host file and applies `action`. Other files stay.
    public static func reconcile(decision: BundledHelperLaunchDecision, checkedPath: String, hostsDirectory: URL, remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) -> Outcome {
        let file = hostsDirectory.appendingPathComponent(zeusHostFileName)
        let named = executablePath(in: file)
        let chosen = action(decision: decision, checkedPath: checkedPath, manifestFileName: zeusHostFileName, manifestExecutablePath: named)
        return apply(action: chosen, in: hostsDirectory, remove: remove)
    }

    private static func executablePath(in file: URL) -> String? {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["path"] as? String
    }
}
