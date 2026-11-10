import AppKit
import ZeusCore

/// "Connect Chrome": registers `zeus-bridge` as Chrome's com.zeus.bridge native host (only the
/// ZEUS extension's ID may start it) and puts the unpacked extension where Load unpacked can
/// find it. Disconnect removes the host registration; Chrome's other hosts are never touched.
enum ChromeInstaller {
    enum InstallError: LocalizedError {
        case extensionMissing(String)

        var errorDescription: String? {
            switch self {
            case .extensionMissing(let path): "The ZEUS extension wasn't found at \(path). Rebuild with scripts/bundle.sh."
            }
        }
    }

    static var installedBridge: URL { ZeusPaths.binDirectory.appendingPathComponent("zeus-bridge") }
    static var bundledExtension: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ChromeExtension") }

    static func isInstalled() -> Bool {
        guard let data = try? Data(contentsOf: ZeusPaths.chromeNativeHostManifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["path"] as? String == installedBridge.path
    }

    static func install() throws {
        try HelperInstaller.refresh("zeus-bridge")
        try refreshExtension()

        let manifest: [String: Any] = [
            "name": ZeusPaths.nativeHostName,
            "description": "ZEUS browser bridge",
            "path": installedBridge.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(ZeusPaths.extensionID)/"],
        ]
        let url = ZeusPaths.chromeNativeHostManifest
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    static func uninstall() throws {
        let url = ZeusPaths.chromeNativeHostManifest
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// Keeps the loaded extension in step with the app. Chrome picks up changes on its next
    /// reload of the extension (or restart). Safe to call on every launch.
    static func refreshExtension() throws {
        let source = bundledExtension
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("manifest.json").path) else {
            throw InstallError.extensionMissing(source.path)
        }
        let destination = ZeusPaths.extensionDirectory
        let staging = destination.deletingLastPathComponent().appendingPathComponent("ChromeExtension.new")
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: staging)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
    }

    /// Opens chrome://extensions in Chrome and shows the folder to pick in Load unpacked.
    static func showLoadUnpacked() {
        NSWorkspace.shared.activateFileViewerSelecting([ZeusPaths.extensionDirectory])
        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
           let url = URL(string: "chrome://extensions/") {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: configuration)
        }
    }
}

/// Copies a helper from Contents/Helpers to ~/Library/Application Support/Zeus/bin, so
/// rebuilding or moving ZEUS never breaks Claude Code or Chrome.
enum HelperInstaller {
    enum HelperError: LocalizedError {
        case missing(String)
        var errorDescription: String? {
            switch self {
            case .missing(let path): "\((path as NSString).lastPathComponent) was not found at \(path). Run ZEUS from its app bundle."
            }
        }
    }

    static func refresh(_ name: String) throws {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)")
        guard FileManager.default.isExecutableFile(atPath: bundled.path) else { throw HelperError.missing(bundled.path) }
        let directory = ZeusPaths.binDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installed = directory.appendingPathComponent(name)
        let staging = directory.appendingPathComponent("\(name).new")
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.copyItem(at: bundled, to: staging)
        if FileManager.default.fileExists(atPath: installed.path) {
            _ = try FileManager.default.replaceItemAt(installed, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: installed)
        }
    }
}
