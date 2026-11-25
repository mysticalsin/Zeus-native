import Foundation

/// One choice Zeus is showing for an agent. A select on Zeus or in the peer app clears it.
/// The first surface to answer is the one that stays recorded. A later select does not open it again.
public struct AgentChoiceDismiss: Equatable, Sendable {
    public enum Surface: Equatable, Sendable {
        case zeus
        case peer
    }

    public var open: Bool
    public var session: String
    public var tool: String
    public var answeredOn: Surface?

    public init(open: Bool, session: String, tool: String, answeredOn: Surface? = nil) {
        self.open = open
        self.session = session
        self.tool = tool
        self.answeredOn = answeredOn
    }

    public static func shown(session: String, tool: String) -> AgentChoiceDismiss {
        AgentChoiceDismiss(open: true, session: session, tool: tool)
    }

    /// "Question" is the card title for Claude's AskUserQuestion tool.
    public static func sameTool(_ lhs: String, _ rhs: String) -> Bool {
        canonical(lhs) == canonical(rhs)
    }

    /// Clears the popup. A peer select for another session or tool leaves this one up.
    /// Returns whether this call closed it.
    @discardableResult
    public mutating func select(on surface: Surface, session: String? = nil, tool: String? = nil) -> Bool {
        guard open else { return false }
        if surface == .peer {
            if let session, session != self.session { return false }
            if let tool, !Self.sameTool(tool, self.tool) { return false }
        }
        open = false
        if answeredOn == nil { answeredOn = surface }
        return true
    }

    private static func canonical(_ tool: String) -> String {
        switch tool {
        case "AskUserQuestion", "Question": "question"
        default: tool
        }
    }
}

/// Whether a peer app already took an AskUserQuestion answer. The detail is the tool result
/// `zeus-hook` forwards, not a live window.
public enum PeerQuestionSelection {
    public static func chose(detail: String?) -> Bool {
        guard let detail, let data = detail.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let answers) = value["answers"] else { return false }
        return answers.values.contains { item in
            guard let text = item.stringValue else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
