import AppKit
import Darwin
import Foundation

/// One-time import of Tony's Anthropic API key from a mode-600 file into the Keychain. Never logs
/// or prints the key. QA7 round 12: `~/.zeus/tony-anthropic-key.txt` → `assistant.key.anthropic`.
enum AssistantKeyImporter {
    private static let defaultPath = NSHomeDirectory() + "/.zeus/tony-anthropic-key.txt"
    private static let account = "assistant.key.anthropic"

    struct Outcome {
        let message: String
        /// Set only after the key is verified in the Keychain: the plaintext source that is still on disk.
        /// Nothing is deleted automatically; the caller offers removal.
        let removableSource: String?
        var imported: Bool { message.hasPrefix("ok") }
    }

    /// Why a key file is unsafe to import, or nil when it is a regular file owned by this user and
    /// closed to group and others. Symlinks are not followed.
    static func insecureReason(mode: mode_t, owner: uid_t, currentUser: uid_t) -> String? {
        if mode & S_IFMT != S_IFREG { return "not a regular file" }
        if owner != currentUser { return "not owned by you" }
        if mode & 0o077 != 0 { return "readable by other users (run chmod 600 on it)" }
        return nil
    }

    /// At launch: import from the default path only when the Keychain slot is still empty.
    static func importDefaultIfNeeded() {
        guard Keychain.get(account) == nil else { return }
        let result = outcome(forFile: defaultPath)
        guard result.imported, let source = result.removableSource else { return }
        // Surface the disclosure and let the user decide; nothing is deleted here.
        Task { @MainActor in offerRemoval(of: source) }
    }

    /// Asks the user (explicit confirmation) whether to delete the plaintext key file after a verified
    /// Keychain store. Cancel keeps the file. Never called automatically with deletion implied.
    @MainActor
    static func offerRemoval(of source: String) {
        let alert = NSAlert()
        alert.messageText = "Anthropic key saved to the Keychain"
        alert.informativeText = "A plaintext copy of the key is still at \(source). Zeus did not delete it. Delete that file now?"
        alert.addButton(withTitle: "Keep File")
        alert.addButton(withTitle: "Delete File")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        _ = removeSource(source)
    }

    /// Deletes the plaintext source only if the Keychain still holds a key and the path is still a
    /// regular file (not a symlink) owned by this user. Returns whether it was removed.
    @discardableResult
    static func removeSource(_ path: String) -> Bool {
        guard Keychain.get(account) != nil else { return false }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else { return false }
        return (try? FileManager.default.removeItem(atPath: path)) != nil
    }

    /// `zeus debug import-assistant-key anthropic <path>` — returns a short status, never the key.
    static func importFromFile(_ path: String) -> String {
        outcome(forFile: path).message
    }

    static func outcome(forFile path: String) -> Outcome {
        let expanded = (path as NSString).expandingTildeInPath
        var info = stat()
        guard lstat(expanded, &info) == 0 else { return Outcome(message: "ERROR file not readable: \(expanded)", removableSource: nil) }
        if let reason = insecureReason(mode: info.st_mode, owner: info.st_uid, currentUser: getuid()) {
            return Outcome(message: "ERROR refusing to import \(expanded): \(reason)", removableSource: nil)
        }
        guard FileManager.default.isReadableFile(atPath: expanded) else { return Outcome(message: "ERROR file not readable: \(expanded)", removableSource: nil) }
        guard let raw = try? String(contentsOfFile: expanded, encoding: .utf8) else { return Outcome(message: "ERROR could not read file", removableSource: nil) }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-ant-"), key.count > 20 else { return Outcome(message: "ERROR file does not look like an Anthropic key", removableSource: nil) }
        guard Keychain.set(key, for: account), Keychain.get(account) == key else {
            return Outcome(message: "ERROR Keychain write failed", removableSource: nil)
        }
        return Outcome(message: "ok assistant.key.anthropic saved from file. A plaintext copy of the key remains at \(expanded); Zeus did not delete it. Remove it yourself once you no longer need it.",
                       removableSource: expanded)
    }
}
