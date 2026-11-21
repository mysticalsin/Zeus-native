import Foundation
import ZeusCore

/// Adds ZEUS's hooks to ~/.claude/settings.json next to whatever is already there (other apps'
/// hooks are left untouched), with a timestamped backup first. Removing them restores nothing
/// else: it only deletes entries whose command runs ZEUS's hook.
enum ClaudeHookInstaller {
    enum InstallError: LocalizedError {
        case unreadableSettings(String)
        case helperRefused(String)

        var errorDescription: String? {
            switch self {
            case .unreadableSettings(let reason): "Could not read ~/.claude/settings.json: \(reason)"
            case .helperRefused(let sentence): sentence
            }
        }
    }

    /// Debug and test builds honour `ZEUS_CLAUDE_SETTINGS` (a copy, for scripts/e2e.sh).
    /// Release builds ignore it.
    static var settingsURL: URL {
        if let override = SupportOverride.resolved("ZEUS_CLAUDE_SETTINGS") {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// The helper inside the signed app bundle. Hook configs name this path, which is the path
    /// the signature check reads. A copy under Application Support is not referenced.
    static var bundledHook: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/zeus-hook")
    }

    static let marker = "zeus-hook"

    /// Guarded so the agent is unaffected if ZEUS is ever deleted. Nil when `hookPath` is not
    /// the checked bundle helper, or when it could break out of the shell quotes.
    static func command(hookPath: String) -> String? {
        guard BundledHelperLaunchPolicy.executableToPublish(checkedPath: hookPath, helperName: "zeus-hook") == hookPath else { return nil }
        guard hookPath.rangeOfCharacter(from: CharacterSet(charactersIn: "\"'`$\\\n")) == nil else { return nil }
        return "/bin/sh -c '[ -x \"\(hookPath)\" ] && \"\(hookPath)\" --source claude-code || true'"
    }

    /// Signature-checks the bundle helper and returns that same path. A failure refuses.
    static func referencedHookPath() throws -> String {
        let path = bundledHook.path
        let decision = BundledHelperLaunch.decide(path: path, signingIdentifier: "zeus-hook")
        guard let published = BundledHelperLaunchPolicy.publishedExecutable(checkedPath: path, helperName: "zeus-hook", decision: decision),
              published == path, command(hookPath: published) != nil else {
            BundledHelperLaunchLog.refused(path: path)
            throw InstallError.helperRefused(BundledHelperLaunchPolicy.refusalSentence)
        }
        return published
    }

    /// (event, matcher, waits for a decision)
    static let events: [(String, String, Bool)] = [
        ("SessionStart", "", false),
        ("UserPromptSubmit", "", false),
        ("PreToolUse", "*", false),
        ("PermissionRequest", "*", true),
        ("Stop", "", false),
        ("StopFailure", "", false),
        ("SessionEnd", "", false),
    ]

    /// Re-checks the bundle helper. When an installed config still names another path, rewrites
    /// Zeus's entries to the checked path. A failed check removes those entries.
    static func refreshHelper() throws {
        let path: String
        do {
            path = try referencedHookPath()
        } catch {
            if isInstalled() { try? uninstall() }
            throw error
        }
        guard isInstalled() else { return }
        let text = (try? String(contentsOf: settingsURL, encoding: .utf8)) ?? ""
        if !text.contains(path) { _ = try install() }
    }

    static func isInstalled() -> Bool {
        guard let text = try? String(contentsOf: settingsURL, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    /// Returns the backup's location.
    @discardableResult
    static func install() throws -> URL? {
        let path = try referencedHookPath()
        guard let command = command(hookPath: path) else {
            throw InstallError.helperRefused(BundledHelperLaunchPolicy.refusalSentence)
        }
        var settings = try readSettings()
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        hooks = removingZeusEntries(from: hooks)
        for (event, matcher, waits) in events {
            var handler: [String: Any] = ["type": "command", "command": command]
            if waits { handler["timeout"] = 120 } else { handler["async"] = true }
            var entries = (hooks[event] as? [[String: Any]]) ?? []
            entries.append(["matcher": matcher, "hooks": [handler]])
            hooks[event] = entries
        }
        settings["hooks"] = hooks
        let backup = try backupSettings()
        try write(settings)
        return backup
    }

    static func uninstall() throws {
        var settings = try readSettings()
        guard let hooks = settings["hooks"] as? [String: Any] else { return }
        _ = try backupSettings()
        settings["hooks"] = removingZeusEntries(from: hooks)
        try write(settings)
    }

    // MARK: Helpers

    private static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadableSettings("not a JSON object")
        }
        return object
    }

    private static func removingZeusEntries(from hooks: [String: Any]) -> [String: Any] {
        var result = hooks
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept = entries.compactMap { entry -> [String: Any]? in
                guard let handlers = entry["hooks"] as? [[String: Any]] else { return entry }
                let others = handlers.filter { !(($0["command"] as? String)?.contains(marker) ?? false) }
                if others.isEmpty { return nil }
                var copy = entry
                copy["hooks"] = others
                return copy
            }
            result[event] = kept.isEmpty ? nil : kept
        }
        return result
    }

    private static func backupSettings() throws -> URL? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let directory = settingsURL.deletingLastPathComponent()
        var backup = directory.appendingPathComponent("settings.json.zeus-backup-\(stamp)")
        var counter = 2
        while FileManager.default.fileExists(atPath: backup.path) { // two clicks in the same second
            backup = directory.appendingPathComponent("settings.json.zeus-backup-\(stamp)-\(counter)")
            counter += 1
        }
        try FileManager.default.copyItem(at: settingsURL, to: backup)
        return backup
    }

    private static func write(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
    }
}
