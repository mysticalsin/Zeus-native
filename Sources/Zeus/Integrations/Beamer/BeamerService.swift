import AppKit
import ApplicationServices
import Observation
import ZeusCore

/// The real Mac behind `BeamerClient`.
struct SystemBeamerEnvironment: BeamerEnvironment {
    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: BeamerFiles.bundleID) != nil
            || FileManager.default.fileExists(atPath: BeamerFiles.appPath)
    }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: BeamerFiles.bundleID).isEmpty }
    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    func settingsData() -> Data? { try? Data(contentsOf: BeamerFiles.settings()) }

    func sendToSocket(_ payload: Data) -> Bool {
        UnixSocket.request(path: BeamerFiles.socket().path, payload: payload, expectReply: false, timeout: 1) != nil
    }

    /// osascript with a 6 second ceiling, so a menu that never answers cannot hang Zeus.
    func runScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(6)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    func launch(window: Bool) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: BeamerFiles.bundleID) ?? URL(string: "file://\(BeamerFiles.appPath)") else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = window ? [] : ["--hidden"]
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        return true
    }
}

/// Settings › Beamer › Install: copies Beamer.app out of the downloaded disk image.
enum BeamerInstaller {
    /// The newest Beamer-*.dmg in Downloads, if any.
    static func downloadedImage(downloads: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("Beamer") && $0.pathExtension.lowercased() == "dmg" }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
    }

    /// hdiutil attach, ditto to /Applications, hdiutil detach. Returns a problem to show, or nil.
    static func install(from image: URL) async -> String? {
        let mount = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("zeus-beamer-\(UUID().uuidString.prefix(6))")
        do { try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true) } catch { return "Couldn't prepare a place to open the disk image." }
        guard await run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noverify", "-mountpoint", mount.path, image.path]) else {
            return "The disk image wouldn't open."
        }
        let app = mount.appendingPathComponent("Beamer.app")
        var problem: String?
        if FileManager.default.fileExists(atPath: app.path) {
            if !(await run("/usr/bin/ditto", [app.path, BeamerFiles.appPath])) { problem = "Copying Beamer to Applications failed." }
        } else {
            problem = "That disk image has no Beamer.app."
        }
        _ = await run("/usr/bin/hdiutil", ["detach", mount.path])
        try? FileManager.default.removeItem(at: mount)
        return problem
    }

    private static func run(_ executable: String, _ arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
    }
}

/// What the Settings page, the Continuity tab and the voice commands share.
@MainActor
@Observable
final class BeamerModel {
    static let shared = BeamerModel()

    private(set) var status = BeamerStatus.missing
    private(set) var busy = false
    var message: String?
    @ObservationIgnored var onCrossing: ((Bool) -> Void)?
    @ObservationIgnored private let client: BeamerClient
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastCrossed: Bool?

    init(client: BeamerClient = BeamerClient(environment: SystemBeamerEnvironment())) { self.client = client }

    var downloadedImage: URL? { BeamerInstaller.downloadedImage() }

    /// Reads state off the main thread (the menu read shells out).
    func refresh() async {
        let client = self.client
        let fresh = await Task.detached { client.status() }.value
        if status != fresh { status = fresh }
        let crossed = fresh.availability == .ready ? fresh.isCrossed : nil
        if let crossed, let before = lastCrossed, crossed != before, SettingsStore.shared.bool("beamer.cue") { onCrossing?(crossed) }
        lastCrossed = crossed
    }

    @discardableResult
    func perform(_ command: BeamerCommand) async -> BeamerOutcome {
        let client = self.client
        busy = true
        let outcome = await Task.detached { client.perform(command) }.value
        busy = false
        message = outcome.message
        try? await Task.sleep(for: .milliseconds(command == .start ? 1500 : 400))
        await refresh()
        return outcome
    }

    func install() async {
        guard let image = downloadedImage else { message = "No Beamer disk image in Downloads. Download Beamer first."; return }
        busy = true
        message = "Installing Beamer…"
        let problem = await BeamerInstaller.install(from: image)
        busy = false
        message = problem ?? "Beamer is in Applications. Open it once and allow what it asks for."
        await refresh()
    }

    /// A page that shows Beamer calls this while it is on screen, so the status keeps up.
    func watch() {
        viewers += 1
        startLoop()
    }

    func unwatch() { viewers = max(0, viewers - 1) }

    /// The cue and the Continuity chip need a slow watcher even with no page open.
    func startBackgroundWatch() { startLoop() }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let wanted = (self?.viewers ?? 0) > 0
                let cue = SettingsStore.shared.bool("beamer.cue")
                let running = self?.status.isRunning ?? false
                try? await Task.sleep(for: .seconds(wanted ? 3 : (cue && running ? 6 : 20)))
            }
        }
    }

    /// Zeus start: opens Beamer in the menu bar when Settings asks for it.
    func startIfWanted() {
        guard SettingsStore.shared.bool("beamer.autoStart") else { return }
        Task { _ = await perform(.start) }
    }
}
