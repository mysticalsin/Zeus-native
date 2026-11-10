import Foundation
import ZeusCore

/// Adds ZEUS's hooks to ~/.claude/settings.json next to whatever is already there (other apps'
/// hooks are left untouched), with a timestamped backup first. Removing them restores nothing
/// else: it only deletes entries whose command runs ZEUS's hook.
enum ClaudeHookInstaller {
    enum InstallError: LocalizedError {
        case unreadableSettings(String)

        var errorDescription: String? {
            switch self {
            case .unreadableSettings(let reason): "Could not read ~/.claude/settings.json: \(reason)"
            }
        }
    }

    /// ZEUS_CLAUDE_SETTINGS points the installer at a copy, for scripts/e2e.sh.
    static var settingsURL: URL {
        if let override = ProcessInfo.processInfo.environment["ZEUS_CLAUDE_SETTINGS"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// A stable copy outside the app bundle, so rebuilding or moving ZEUS never breaks Claude Code.
    static var installedHook: URL {
        ZeusPaths.binDirectory.appendingPathComponent("zeus-hook")
    }

    static let marker = "Zeus/bin/zeus-hook"

    /// Guarded so Claude Code is unaffected if ZEUS is ever deleted.
    static var command: String {
        let path = "$HOME/Library/Application Support/Zeus/bin/zeus-hook"
        return "/bin/sh -c '[ -x \"\(path)\" ] && \"\(path)\" --source claude-code || true'"
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

    /// Copies the bundled helper to its stable location. Safe to call on every launch.
    static func refreshHelper() throws {
        try HelperInstaller.refresh("zeus-hook")
    }

    static func isInstalled() -> Bool {
        guard let text = try? String(contentsOf: settingsURL, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    /// Returns the backup's location.
    @discardableResult
    static func install() throws -> URL? {
        try refreshHelper()
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
