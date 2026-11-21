import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

    /// On a refusal, remove Zeus's own host file unless its path is one this check accepted.
    /// A passing check keeps the file. Any other file name stays.
    public static func action(
        decision: BundledHelperLaunchDecision,
        checkedPath: String,
        manifestFileName: String,
        manifestExecutablePath: String?,
        passedPaths: Set<String> = []
    ) -> Action {
        _ = checkedPath
        guard manifestFileName == zeusHostFileName else { return .keep }
        guard case .refuse = decision else { return .keep }
        let named = manifestExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !named.isEmpty, passedPaths.contains(named) { return .keep }
        return .remove
    }

    /// Deletes `com.zeus.bridge.json` when the action is remove. No other file name is removed.
    /// A delete that throws is `removalFailed` and the file is left as it was.
    public static func apply(action: Action, in directory: URL, remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) -> Outcome {
        guard action == .remove else { return .kept }
        let url = directory.appendingPathComponent(zeusHostFileName)
        guard nodeExists(url.path) else { return .removed }
        do {
            try remove(url)
            return .removed
        } catch {
            return .removalFailed
        }
    }

    /// Reads the `path` in Zeus's own host file and applies `action`. Other files stay.
    public static func reconcile(
        decision: BundledHelperLaunchDecision,
        checkedPath: String,
        hostsDirectory: URL,
        passedPaths: Set<String> = [],
        remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) -> Outcome {
        let file = hostsDirectory.appendingPathComponent(zeusHostFileName)
        let named = executablePath(in: file)
        let chosen = action(decision: decision, checkedPath: checkedPath, manifestFileName: zeusHostFileName,
                            manifestExecutablePath: named, passedPaths: passedPaths)
        return apply(action: chosen, in: hostsDirectory, remove: remove)
    }

    /// `fileExists` follows links and reports a dangling symlink as absent.
    private static func nodeExists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    private static func executablePath(in file: URL) -> String? {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["path"] as? String
    }
}
