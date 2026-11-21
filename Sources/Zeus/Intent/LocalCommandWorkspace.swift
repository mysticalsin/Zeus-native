import AppKit
import ZeusCore

/// Performs a local command with NSWorkspace for apps, and with the helpers Zeus already
/// uses for media keys and output volume. No new permission, prompt, or entitlement.
@MainActor
enum LocalCommandWorkspace {
    /// Installed apps from the in-memory index, with running state from NSWorkspace.
    /// Unsaved documents are unknown: NSWorkspace does not report them, so quit asks.
    static func installedApps() -> [LocalApp] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return AppIndex.shared.snapshot().map { entry in
            LocalApp(name: entry.name, bundleID: entry.bundleID, path: entry.path, aliases: entry.aliases,
                     isRunning: running.contains(entry.bundleID), hasUnsavedState: nil)
        }
    }

    static func perform(_ action: LocalCommandAction) {
        switch action {
        case .open(let app), .switchTo(let app):
            bringForward(app)
        case .quit(let app):
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == app.bundleID }?.terminate()
        case .media(let command):
            switch command {
            case .play, .pause: MediaKeys.post(.play)
            case .next: MediaKeys.post(.next)
            }
        case .volume(let change):
            _ = SystemVolume.apply(fastVolume(change))
        }
    }

    static func summary(_ action: LocalCommandAction) -> String {
        switch action {
        case .open(let app): "open \(app.name)"
        case .quit(let app): "quit \(app.name)"
        case .switchTo(let app): "switch \(app.name)"
        case .media(let command): "media \(command.rawValue)"
        case .volume(let change):
            switch change {
            case .up: "volume up"
            case .down: "volume down"
            case .mute: "volume mute"
            case .unmute: "volume unmute"
            case .set(let value): "volume \(value)"
            }
        }
    }

    private static func bringForward(_ app: LocalApp) {
        let workspace = NSWorkspace.shared
        if let running = workspace.runningApplications.first(where: { $0.bundleIdentifier == app.bundleID }) {
            _ = running.activate(options: [.activateAllWindows])
            return
        }
        let url: URL?
        if !app.path.isEmpty {
            url = URL(fileURLWithPath: app.path)
        } else {
            url = workspace.urlForApplication(withBundleIdentifier: app.bundleID)
        }
        guard let url else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration) { _, _ in }
    }

    private static func fastVolume(_ change: LocalVolume) -> FastIntent.Volume {
        switch change {
        case .up: .up
        case .down: .down
        case .mute: .mute
        case .unmute: .unmute
        case .set(let value): .set(value)
        }
    }
}
