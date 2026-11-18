import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum ZeusPaths {
    public static let bundleIdentifier = "app.zeus.mac"
    public static let nativeHostName = "com.zeus.bridge"
    /// Fixed by the public `key` in extension/manifest.json, so it is the same wherever the
    /// unpacked extension is loaded from.
    public static let extensionID = "dkpclhaealkdnnihlccglmonmmjfjobe"

    /// ~/Library/Application Support/Zeus. A debug build may move it with `ZEUS_SUPPORT_DIR` when that
    /// directory is this user's and mode 0700. A release build ignores the variable.
    public static var supportDirectory: URL {
        if let override = SupportDirectoryRule.resolved() {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Zeus", isDirectory: true)
    }

    /// Unix socket shared by the app, `zeus-hook` and `zeus-bridge`.
    /// `ZEUS_SOCKET` moves just the socket.
    public static var socket: URL {
        if let override = ProcessInfo.processInfo.environment["ZEUS_SOCKET"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return supportDirectory.appendingPathComponent("zeus.sock")
    }

    /// Served by `zeus-bridge` while Chrome has it running; the app sends browser requests here.
    public static var chromeSocket: URL { supportDirectory.appendingPathComponent("chrome.sock") }

    /// Stable copies of the helpers, outside the app bundle.
    public static var binDirectory: URL { supportDirectory.appendingPathComponent("bin", isDirectory: true) }

    /// Where "Connect Chrome" puts the unpacked extension for Load unpacked.
    public static var extensionDirectory: URL {
        supportDirectory.appendingPathComponent("ChromeExtension", isDirectory: true)
    }

    /// The lid-closed (Insomnia) recovery journal, written before every system change.
    public static var insomniaJournal: URL { supportDirectory.appendingPathComponent("insomnia-journal.json") }

    /// Every hands command and shell gate verdict, one line each. Local only.
    public static var handsLog: URL { supportDirectory.appendingPathComponent("hands-commands.log") }

    /// Saved "when I say X, do Y" shortcuts.
    public static var learnedShortcuts: URL { supportDirectory.appendingPathComponent("learned-shortcuts.json") }

    /// Working directory for one brain turn.
    public static func runDirectory(turn: UUID) -> URL {
        supportDirectory.appendingPathComponent("runs/\(turn.uuidString)", isDirectory: true)
    }

    public static var chromeNativeHostManifest: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts/\(nativeHostName).json")
    }
}

public struct SupportDirectoryFacts: Equatable, Sendable {
    public var isSymlink: Bool
    public var uid: UInt32
    /// Permission bits only (`st_mode & 0777`), not the file type.
    public var mode: UInt32

    public init(isSymlink: Bool, uid: UInt32, mode: UInt32) {
        self.isSymlink = isSymlink
        self.uid = uid
        self.mode = mode
    }
}

public enum SupportDirectoryRule {
    /// The override exists for tests and debug builds. A release build never honours it.
    public static var allowOverride: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Usable only when the override is allowed and `lstat` says this user owns a real directory at 0700.
    public static func accepted(path: String, allowOverride: Bool, uid: UInt32, facts: SupportDirectoryFacts?) -> String? {
        guard allowOverride, !path.isEmpty, let facts else { return nil }
        guard !facts.isSymlink, facts.uid == uid, (facts.mode & 0o777) == 0o700 else { return nil }
        return path
    }

    public static func facts(at path: String) -> SupportDirectoryFacts? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let type = info.st_mode & mode_t(S_IFMT)
        return SupportDirectoryFacts(isSymlink: type == mode_t(S_IFLNK), uid: info.st_uid, mode: UInt32(info.st_mode))
    }

    /// The relocated support directory, or nil when the override is absent, forbidden, or not a private directory.
    public static func resolved(environment: [String: String] = ProcessInfo.processInfo.environment,
                                allowOverride: Bool = SupportDirectoryRule.allowOverride,
                                uid: UInt32 = UInt32(geteuid())) -> String? {
        guard let path = environment["ZEUS_SUPPORT_DIR"], !path.isEmpty else { return nil }
        return accepted(path: path, allowOverride: allowOverride, uid: uid, facts: facts(at: path))
    }
}
