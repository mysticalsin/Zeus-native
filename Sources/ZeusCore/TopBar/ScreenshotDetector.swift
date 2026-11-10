import Foundation

/// Detects macOS screenshot files across various languages (English, French, Portuguese, Spanish, German, Italian, etc.)
/// and resolves the configured macOS screenshot destination directory.
public enum ScreenshotDetector {
    public static let localizedPrefixes: [String] = [
        "screenshot",
        "screen shot",
        "capture d’écran",
        "capture d'écran",
        "capture d’ecran",
        "capture d'ecran",
        "captura de tela",
        "captura de ecrã",
        "captura de ecra",
        "captura de pantalla",
        "bildschirmfoto",
        "istantanea",
        "снимок экрана",
        "スクリーンショット",
        "截屏",
        "屏幕截图",
    ]

    public static let validExtensions: Set<String> = [
        "png", "jpg", "jpeg", "pdf", "tiff", "heic", "mov", "mp4"
    ]

    public static func isScreenshot(filename: String) -> Bool {
        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.hasPrefix(".") else { return false }

        let pathExtension = (name as NSString).pathExtension.lowercased()
        guard validExtensions.contains(pathExtension) else { return false }

        let baseName = (name as NSString).deletingPathExtension.lowercased()

        return localizedPrefixes.contains { prefix in
            baseName.hasPrefix(prefix)
        }
    }

    public static func isScreenshot(url: URL) -> Bool {
        isScreenshot(filename: url.lastPathComponent)
    }

    public static func location(defaults: UserDefaults = .standard) -> URL {
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let expanded = (custom as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }
}
