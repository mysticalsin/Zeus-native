import AppKit

/// Opens a reply URL in the alert's own app (not whatever the system default for the scheme is), and brings it forward.
@MainActor
enum AlertReplyLauncher {
    /// False when the app is not installed.
    static func open(_ url: URL, bundleID: String) -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, _ in }
        return true
    }
}
