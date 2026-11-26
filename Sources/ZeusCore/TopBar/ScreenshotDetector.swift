import Foundation

/// Detects macOS screenshot files across various languages (English, French, Portuguese, Spanish, German, Italian, etc.)
/// and resolves the configured macOS screenshot destination directory.
public enum ScreenshotDetector {
    public static let localizedPrefixes: [String] = ScreenshotDetectorBox.localizedPrefixes

    public static let validExtensions: Set<String> = ScreenshotDetectorBox.validExtensions

    public static func isScreenshot(filename: String) -> Bool {
        ScreenshotDetectorBox.isScreenshot(filename: filename)
    }

    public static func isScreenshot(url: URL) -> Bool {
        ScreenshotDetectorBox.isScreenshot(url: url)
    }

    public static func location(defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.screencapture")) -> URL {
        resolveLocation(configuredPath: defaults?.string(forKey: "location"),
            desktop: FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
            expandPath: { ($0 as NSString).expandingTildeInPath },
            exists: { FileManager.default.fileExists(atPath: $0) })
    }

    /// Resolve only the supplied state; tests need no screenshot preferences or private paths.
    public static func resolveLocation(configuredPath: String?, desktop: URL,
                                       expandPath: (String) -> String, exists: (String) -> Bool) -> URL {
        ScreenshotDetectorBox.resolveLocation(configuredPath: configuredPath, desktop: desktop,
            expandPath: expandPath, exists: exists)
    }
}
