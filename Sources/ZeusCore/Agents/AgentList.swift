import Foundation

/// What one row in the agents list says. Opening a row shows its detail here. It does not open a terminal.
public enum AgentList {
    public static let rowOpensDetails = true
    public static let rowJumpsToTerminal = false

    public static func word(_ status: AgentRunState) -> String {
        switch status {
        case .working: "Working"
        case .needsYou, .stalled: "Waiting for you"
        case .failed: "Error"
        case .done, .idle: "Done"
        }
    }

    public static func voice(_ name: String, project: String, status: AgentRunState, activity: String) -> String {
        "\(name), \(project), \(word(status)), \(activity)"
    }
}
