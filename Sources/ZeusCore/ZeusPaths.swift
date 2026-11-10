import Foundation

public enum ZeusPaths {
    public static let bundleIdentifier = "app.zeus.mac"
    public static let nativeHostName = "com.zeus.bridge"
    /// Fixed by the public `key` in extension/manifest.json, so it is the same wherever the
    /// unpacked extension is loaded from.
    public static let extensionID = "dkpclhaealkdnnihlccglmonmmjfjobe"

    /// ~/Library/Application Support/Zeus. `ZEUS_SUPPORT_DIR` moves it (tests, a second build),
    /// so a ZEUS you are running is never touched.
    public static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["ZEUS_SUPPORT_DIR"], !override.isEmpty {
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
