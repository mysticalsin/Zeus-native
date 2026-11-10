import Foundation

/// The Mac side of talking to Beamer, so the client can be tested without it.
public protocol BeamerEnvironment: Sendable {
    var isInstalled: Bool { get }
    var isRunning: Bool { get }
    var accessibilityGranted: Bool { get }
    func settingsData() -> Data?
    /// Sends the word to Beamer's instance socket. False when nothing is listening.
    func sendToSocket(_ payload: Data) -> Bool
    /// Runs AppleScript. nil when it failed or was refused.
    func runScript(_ source: String) -> String?
    /// Opens Beamer (hidden in the menu bar unless `window`).
    func launch(window: Bool) -> Bool
}

/// What a command did, in words Zeus can say.
public struct BeamerOutcome: Equatable, Sendable {
    public var ok: Bool
    public var message: String
    public init(ok: Bool, message: String) { self.ok = ok; self.message = message }
}

/// Reads Beamer's state and sends it commands. Everything that cannot work says why:
/// not installed, not running, or Accessibility missing.
public struct BeamerClient: Sendable {
    public let environment: BeamerEnvironment

    public init(environment: BeamerEnvironment) { self.environment = environment }

    public func status() -> BeamerStatus {
        guard environment.isInstalled else { return .missing }
        let machines = environment.settingsData().map(BeamerSettingsFile.machines(from:)) ?? []
        guard environment.isRunning else {
            return BeamerStatus(availability: .notRunning, version: nil, machines: machines, link: .idle, paused: nil)
        }
        guard environment.accessibilityGranted, let output = environment.runScript(BeamerScripts.menuTitles) else {
            return BeamerStatus(availability: .needsPermission, version: nil, machines: machines, link: .idle, paused: nil)
        }
        let menu = BeamerMenuState.parse(titles: BeamerScripts.titles(fromOutput: output))
        return BeamerStatus(availability: .ready, version: menu.version, machines: machines, link: menu.link, paused: menu.paused)
    }

    public func perform(_ command: BeamerCommand) -> BeamerOutcome {
        guard environment.isInstalled else { return BeamerOutcome(ok: false, message: "Beamer isn't installed. Settings › Beamer can install it.") }
        switch command {
        case .start:
            if environment.isRunning { return BeamerOutcome(ok: true, message: "Beamer is already running.") }
            return environment.launch(window: false) ? BeamerOutcome(ok: true, message: "Starting Beamer.") : BeamerOutcome(ok: false, message: "Beamer didn't open.")
        case .showWindow:
            if !environment.isRunning {
                return environment.launch(window: true) ? BeamerOutcome(ok: true, message: "Opening Beamer.") : BeamerOutcome(ok: false, message: "Beamer didn't open.")
            }
            return environment.sendToSocket(BeamerMessage.activate)
                ? BeamerOutcome(ok: true, message: "Opening Beamer.")
                : (environment.launch(window: true) ? BeamerOutcome(ok: true, message: "Opening Beamer.") : BeamerOutcome(ok: false, message: "Beamer didn't answer."))
        case .pause, .resume, .returnHome, .switchTo:
            return menuCommand(command)
        }
    }

    private func menuCommand(_ command: BeamerCommand) -> BeamerOutcome {
        guard environment.isRunning else { return BeamerOutcome(ok: false, message: "Beamer isn't running. Say start Beamer first.") }
        guard environment.accessibilityGranted else {
            return BeamerOutcome(ok: false, message: "Beamer can only be steered with Accessibility. Allow Zeus in Settings › Permissions.")
        }
        guard let output = environment.runScript(BeamerScripts.menuTitles) else {
            return BeamerOutcome(ok: false, message: "macOS wouldn't let Zeus read Beamer's menu. Allow Zeus to control System Events when asked.")
        }
        let menu = BeamerMenuState.parse(titles: BeamerScripts.titles(fromOutput: output))
        switch command {
        case .pause:
            if menu.paused == true { return BeamerOutcome(ok: true, message: "Crossing is already paused.") }
            return click("Pause crossing", done: "Paused crossing.")
        case .resume:
            if menu.paused == false { return BeamerOutcome(ok: true, message: "Crossing isn't paused.") }
            return click("Resume crossing", done: "Crossing is back on.")
        case .returnHome:
            guard menu.link != .idle else { return BeamerOutcome(ok: true, message: "Input is already on this Mac.") }
            let title = output.split(whereSeparator: \.isNewline).map(String.init).first { $0 == "Return input to Mac" || $0.hasPrefix("Bring input back") }
            return title.map { click($0, done: "Input is back on this Mac.") } ?? BeamerOutcome(ok: false, message: "Beamer has nothing to bring back.")
        case .switchTo(let spoken):
            if BeamerMatching.isIPad(spoken), !menu.targets.contains(where: BeamerMatching.isIPad) {
                return BeamerOutcome(ok: false, message: "Beamer doesn't pair iPads. Use Universal Control for the iPad.")
            }
            if menu.targets.isEmpty {
                // One machine: the plain "Send input" item stands for it.
                guard menu.canSend else { return BeamerOutcome(ok: false, message: "Beamer has no machine to send input to. Pair one in Beamer.") }
                return click("Send input", done: "Sending your keyboard and mouse across.")
            }
            guard let name = BeamerMatching.machine(named: spoken, in: menu.targets) else {
                return BeamerOutcome(ok: false, message: "I don't see \(spoken) in Beamer. It has \(menu.targets.joined(separator: ", ")).")
            }
            return click("Send input to \(name)", done: "Sending your keyboard and mouse to \(name).")
        default:
            return BeamerOutcome(ok: false, message: "Unsupported.")
        }
    }

    private func click(_ title: String, done: String) -> BeamerOutcome {
        environment.runScript(BeamerScripts.click(title: title)) != nil
            ? BeamerOutcome(ok: true, message: done)
            : BeamerOutcome(ok: false, message: "Beamer's menu didn't respond to “\(title)”.")
    }
}
