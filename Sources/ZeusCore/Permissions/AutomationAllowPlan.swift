/// What "Allow" and "Allow more" in Settings > Automation should do, as a pure decision.
///
/// The button used to ask every running player. When the only app open was already allowed it
/// returned "granted" and nothing visible happened; apps that were not open were never asked and
/// nothing said so; and an app macOS had refused (it never prompts for that app again) failed
/// silently. The plan targets only the apps not yet allowed, names the ones to open, and sends a
/// refused app to the Automation pane with one sentence.
public enum AutomationAllowPlan {
    public struct Target: Equatable, Sendable {
        public var id: String
        public var name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }

    public enum Access: Equatable, Sendable {
        case allowed
        /// macOS refused this app (errAEEventNotPermitted). It will not ask again.
        case refused
        /// Not asked yet, or not known yet.
        case undecided
    }

    public struct Plan: Equatable, Sendable {
        /// Running, not allowed, not refused: raise macOS's consent sheet for these.
        public var ask: [String] = []
        /// Running apps macOS already refused: only System Settings can turn them on.
        public var refused: [Target] = []
        public var message: String?
        public var opensAutomationPane = false

        public init() {}
    }

    public static func plan(targets: [Target], access: [String: Access], running: Set<String>) -> Plan {
        let missing = targets.filter { (access[$0.id] ?? .undecided) != .allowed }
        guard !missing.isEmpty else { return Plan() }
        let anyAllowed = missing.count < targets.count
        let runningMissing = missing.filter { running.contains($0.id) }
        let refused = runningMissing.filter { access[$0.id] == .refused }
        let askable = runningMissing.filter { access[$0.id] != .refused }
        if askable.isEmpty && refused.isEmpty {
            let button = anyAllowed ? "Allow more" : "Allow"
            return Plan(message: "Open \(list(missing.map(\.name), joiner: "or")), then press \(button).")
        }
        var plan = Plan(ask: askable.map(\.id), refused: refused)
        if askable.isEmpty {
            plan.message = turnOn(refused)
            plan.opensAutomationPane = true
        }
        return plan
    }

    /// After the sheet: the asked apps that did not come back allowed need System Settings.
    public static func afterAsking(targets: [Target], granted: [String: Bool], alreadyRefused: [Target]) -> Plan {
        let declined = targets.filter { granted[$0.id] == false } + alreadyRefused
        guard !declined.isEmpty else { return Plan() }
        return Plan(refused: declined, message: turnOn(declined), opensAutomationPane: true)
    }

    private static func turnOn(_ apps: [Target]) -> String {
        "Turn on Zeus for \(list(apps.map(\.name), joiner: "and")) in Automation."
    }

    /// "Spotify", "Spotify or Keynote", "Spotify, Keynote or PowerPoint".
    public static func list(_ names: [String], joiner: String) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " " + joiner + " " + names[names.count - 1]
        }
    }
}
