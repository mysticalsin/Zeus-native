import Foundation
import ZeusCore

/// Installs and removes the lid-closed admin rule and the backstop agent. One macOS admin prompt
/// each way (`osascript … with administrator privileges`): macOS asks for the password, Zeus never
/// sees it. Runs only when Tony clicks Set up or Remove. The runner is injected for tests.
struct InsomniaInstaller: Sendable {
    enum Status: Equatable, Sendable {
        case installed
        case notInstalled
        /// The file is there but sudo does not allow the command (edited, or another user's rule).
        case needsRepair(String)

        var isReady: Bool { self == .installed }

        var text: String {
            switch self {
            case .installed: "Set up. Zeus can keep the Mac awake with the lid closed."
            case .notInstalled: "Not set up. Lid-closed mode needs a one-time admin rule."
            case .needsRepair(let why): "The rule is there but does not work: \(why). Set it up again."
            }
        }
    }

    enum Outcome: Equatable, Sendable {
        case done(String)
        case cancelled
        case failed(String)

        var text: String {
            switch self {
            case .done(let text): text
            case .cancelled: "Cancelled. Nothing changed."
            case .failed(let text): text
            }
        }
    }

    let runner: any InsomniaCommandRunner
    let user: String
    let uid: UInt32
    let home: URL
    let temporaryDirectory: URL
    let cliPath: String
    let logPath: String
    let fileExists: @Sendable (String) -> Bool

    init(runner: any InsomniaCommandRunner = ProcessCommandRunner(timeout: 300),
         user: String = NSUserName(),
         uid: UInt32 = getuid(),
         home: URL = FileManager.default.homeDirectoryForCurrentUser,
         temporaryDirectory: URL = FileManager.default.temporaryDirectory,
         cliPath: String = InsomniaInstaller.defaultCLIPath(),
         logPath: String = ZeusPaths.supportDirectory.appendingPathComponent("insomnia-guard.log").path,
         fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.runner = runner
        self.user = user
        self.uid = uid
        self.home = home
        self.temporaryDirectory = temporaryDirectory
        self.cliPath = cliPath
        self.logPath = logPath
        self.fileExists = fileExists
    }

    /// The `zeus` CLI copy in Zeus's bin folder, else the one in the bundle, else next to this binary (dev).
    static func defaultCLIPath() -> String {
        let installed = ZeusPaths.binDirectory.appendingPathComponent("zeus").path
        if FileManager.default.isExecutableFile(atPath: installed) { return installed }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/zeus").path
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        return Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("zeus-cli").path ?? installed
    }

    var plistURL: URL { InsomniaBackstop.plistURL(home: home) }

    /// Whether the rule file exists and `sudo -n -l` allows the command without a password.
    func status() -> Status {
        guard fileExists(InsomniaSudoers.path) else { return .notInstalled }
        let (tool, args) = InsomniaCommand.sudoAllows()
        let result = runner.run(tool, args)
        if result.ok { return .installed }
        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .needsRepair(detail.isEmpty ? "sudo said no" : detail)
    }

    func install() -> Outcome {
        let rule: String
        do { rule = try InsomniaSudoers.rule(user: user) } catch {
            return .failed("Your account name \(user) cannot go into a sudoers rule.")
        }
        let ruleFile = temporaryDirectory.appendingPathComponent("zeus-insomnia-\(UUID().uuidString).sudoers")
        defer { try? FileManager.default.removeItem(at: ruleFile) }
        do {
            try Data(rule.utf8).write(to: ruleFile, options: .atomic)
            // The plist needs no admin: it goes in Tony's own LaunchAgents folder.
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: logPath).deletingLastPathComponent(), withIntermediateDirectories: true)
            try InsomniaBackstop.plist(cliPath: cliPath, logPath: logPath).write(to: plistURL, options: .atomic)
        } catch {
            return .failed("Could not prepare the files: \(error.localizedDescription)")
        }
        let script = InsomniaAdminScript.install(ruleFile: ruleFile.path, plist: plistURL.path, uid: uid)
        let result = runner.run(InsomniaCommand.osascript, InsomniaAdminScript.osascriptArguments(
            script, prompt: "Zeus wants to set up lid-closed mode: four pmset commands without a password."))
        if let outcome = Self.failure(result) {
            try? FileManager.default.removeItem(at: plistURL)
            return outcome
        }
        switch status() {
        case .installed: return .done("Set up. Close the lid and agents keep working.")
        case .notInstalled: return .failed("The rule did not appear in /etc/sudoers.d.")
        case .needsRepair(let why): return .failed("Installed, but sudo does not allow it yet: \(why)")
        }
    }

    func uninstall() -> Outcome {
        let script = InsomniaAdminScript.uninstall(plist: plistURL.path, uid: uid)
        let result = runner.run(InsomniaCommand.osascript, InsomniaAdminScript.osascriptArguments(
            script, prompt: "Zeus wants to remove its lid-closed mode rule."))
        if let outcome = Self.failure(result) { return outcome }
        try? FileManager.default.removeItem(at: plistURL)
        return .done("Removed. The Mac sleeps with the lid closed again.")
    }

    /// osascript exits 1 with -128 when the person clicks Cancel.
    private static func failure(_ result: InsomniaCommandResult) -> Outcome? {
        guard !result.ok else { return nil }
        if result.stderr.contains("-128") { return .cancelled }
        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(detail.isEmpty ? "The admin step failed (exit \(result.status))." : detail)
    }
}
