import AppKit
import ZeusCore

/// Opens a terminal window for a `TerminalJob` in Tony's terminal app. The script and the steps come
/// from `TerminalScript` (pure, unit tested); this file only writes the script and runs `open`.
@MainActor
enum TerminalLauncher {
    /// Ghostty, iTerm, Warp or Terminal: Settings' choice, else the one that is open, else a
    /// non-Terminal app that opens .command files, else an installed one, else Terminal.
    static func chooseApp(defaults: UserDefaults = .standard) -> TerminalApp {
        let workspace = NSWorkspace.shared
        let installed = Set(TerminalApp.allCases.map(\.bundleID).filter { workspace.urlForApplication(withBundleIdentifier: $0) != nil })
        let handler = workspace.urlForApplication(toOpen: URL(fileURLWithPath: "/tmp/zeus.command")).flatMap { Bundle(url: $0)?.bundleIdentifier }
        let chosen = TerminalApp.choose(
            preference: defaults.string(forKey: TerminalApp.preferenceKey),
            frontmost: workspace.frontmostApplication?.bundleIdentifier,
            running: workspace.runningApplications.compactMap(\.bundleIdentifier),
            commandHandler: handler, installed: installed)
        // A stale choice (an app since removed) falls back to Terminal.
        return installed.contains(chosen.bundleID) ? chosen : .terminal
    }

    /// Writes the script, runs the steps. Returns the terminal used, or a problem to say.
    static func launch(_ job: TerminalJob) async -> (app: TerminalApp, problem: String?) {
        let app = chooseApp()
        let token = UUID().uuidString.prefix(8).lowercased()
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("zeus-terminal", isDirectory: true)
        let script = folder.appendingPathComponent("\(token).command")
        let steps = TerminalScript.steps(app: app, scriptPath: script.path, directory: job.directory, token: String(token))
        let cleanup = steps.compactMap { step -> String? in
            if case .writeFile(let path, _) = step { return path }
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(TerminalScript.contents(for: job, scriptPath: script.path, cleanup: cleanup).utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            for step in steps {
                switch step {
                case .writeFile(let path, let contents):
                    try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                    try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
                case .run(let executable, let arguments):
                    guard await run(executable, arguments) else { return (app, "\(app.title) didn't open.") }
                }
            }
        } catch {
            return (app, "I couldn't set up the terminal: \(error.localizedDescription)")
        }
        return (app, nil)
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
