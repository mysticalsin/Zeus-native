import AppKit
import ZeusCore

/// "Connect Chrome": registers `zeus-bridge` as Chrome's com.zeus.bridge native host (only the
/// ZEUS extension's ID may start it) and puts the unpacked extension where Load unpacked can
/// find it. Disconnect removes the host registration; Chrome's other hosts are never touched.
enum ChromeInstaller {
    enum InstallError: LocalizedError {
        case extensionMissing(String)
        case helperRefused(String)

        var errorDescription: String? {
            switch self {
            case .extensionMissing(let path): "The Zeus extension wasn't found at \(path). Rebuild with scripts/bundle.sh."
            case .helperRefused(let sentence): sentence
            }
        }
    }

    /// The helper inside the signed app bundle. The native-messaging manifest names this path,
    /// the same path the signature check reads. A copy under Application Support is not used.
    static var bridgeExecutable: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/zeus-bridge")
    }
    static var bundledExtension: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ChromeExtension") }

    static func hasManifest() -> Bool {
        FileManager.default.fileExists(atPath: ZeusPaths.chromeNativeHostManifest.path)
    }

    static func manifestExecutable() -> String? {
        guard let data = try? Data(contentsOf: ZeusPaths.chromeNativeHostManifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["path"] as? String
    }

    static func isInstalled() -> Bool {
        manifestExecutable() == bridgeExecutable.path
    }

    /// Checks the bridge inside the app bundle. A refusal removes Zeus's own host registration
    /// when that file names the refused path or a user-writable copy of zeus-bridge. Other host
    /// files stay. A pass points the registration at the same bundle path, then drops a
    /// support-directory copy.
    static func authorizeInstalledBridge() -> Result<Void, InstallError> {
        let path = bridgeExecutable.path
        let decision = BundledHelperLaunch.decide(path: path, signingIdentifier: BundledHelperLaunchPolicy.bridgeSigningIdentifier)
        guard let published = BundledHelperLaunchPolicy.publishedExecutable(
            checkedPath: path, helperName: BundledHelperLaunchPolicy.bridgeSigningIdentifier, decision: decision),
              published == path else {
            BundledHelperLaunchLog.refused(path: path)
            let hosts = ZeusPaths.chromeNativeHostManifest.deletingLastPathComponent()
            try? NativeHostRegistration.reconcile(decision: decision, checkedPath: path, hostsDirectory: hosts)
            return .failure(.helperRefused(BundledHelperLaunchPolicy.refusalSentence))
        }
        if hasManifest(), manifestExecutable() != published {
            do { try writeManifest(path: published) } catch {
                return .failure(.helperRefused(BundledHelperLaunchPolicy.refusalSentence))
            }
        }
        if hasManifest() { removeSupportCopy() }
        return .success(())
    }

    static func install() throws {
        switch authorizeInstalledBridge() {
        case .success:
            break
        case .failure(let error):
            throw error
        }
        try refreshExtension()
        let path = bridgeExecutable.path
        guard BundledHelperLaunchPolicy.executableToPublish(checkedPath: path, helperName: BundledHelperLaunchPolicy.bridgeSigningIdentifier) == path else {
            throw InstallError.helperRefused(BundledHelperLaunchPolicy.refusalSentence)
        }
        try writeManifest(path: path)
        removeSupportCopy()
    }

    private static func writeManifest(path: String) throws {
        let manifest: [String: Any] = [
            "name": ZeusPaths.nativeHostName,
            "description": "Zeus browser bridge",
            "path": path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(ZeusPaths.extensionID)/"],
        ]
        let url = ZeusPaths.chromeNativeHostManifest
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    /// Drops a support-directory copy so a stale manifest cannot be the thing the browser runs.
    private static func removeSupportCopy() {
        let copy = ZeusPaths.binDirectory.appendingPathComponent(BundledHelperLaunchPolicy.bridgeSigningIdentifier)
        if FileManager.default.fileExists(atPath: copy.path) {
            try? FileManager.default.removeItem(at: copy)
        }
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

    /// Opens chrome://extensions in the Chrome that is already running, for the Reload button on the Zeus card.
    /// Does nothing when Chrome is not running: it never starts Chrome and never shows the Load unpacked folder.
    static func showExtensionsPage() {
        guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first,
              let app = chrome.bundleURL, let url = URL(string: "chrome://extensions/") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
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

/// Copies a helper out of Contents/Helpers only after the same signature gate the launch
/// sites use. Native-messaging hosts and hook configs are not pointed at the copy.
enum HelperInstaller {
    enum HelperError: LocalizedError {
        case missing(String)
        case refused(String)
        var errorDescription: String? {
            switch self {
            case .missing(let path): "\((path as NSString).lastPathComponent) was not found at \(path). Run Zeus from its app bundle."
            case .refused(let sentence): sentence
            }
        }
    }

    static func refresh(_ name: String) throws {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)")
        let identifier = BundledHelperLaunchPolicy.signingIdentifier(forExecutablePath: bundled.path)
        let decision = BundledHelperLaunch.decide(path: bundled.path, signingIdentifier: identifier)
        guard let published = BundledHelperLaunchPolicy.publishedExecutable(checkedPath: bundled.path, helperName: identifier, decision: decision),
              published == bundled.path else {
            BundledHelperLaunchLog.refused(path: bundled.path)
            throw HelperError.refused(BundledHelperLaunchPolicy.refusalSentence)
        }
        guard FileManager.default.isExecutableFile(atPath: published) else { throw HelperError.missing(published) }
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
