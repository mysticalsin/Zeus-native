import Foundation

public struct AgentStep: Codable, Equatable, Sendable {
    public var title: String
    public var detail: String
    public var date: Date

    public init(title: String, detail: String = "", date: Date = Date()) {
        self.title = title
        self.detail = detail
        self.date = date
    }
}

/// One background agent chip with live steps and steering into the same run.
public struct BackgroundAgentSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var steps: [AgentStep]
    public var steerMessages: [String]
    public var started: Date
    public var finished: Date?
    public var engine: RouterEngine?

    public init(id: UUID = UUID(), title: String, steps: [AgentStep] = [], steerMessages: [String] = [],
                started: Date = Date(), finished: Date? = nil, engine: RouterEngine? = .ollama) {
        self.id = id
        self.title = title
        self.steps = steps
        self.steerMessages = steerMessages
        self.started = started
        self.finished = finished
        self.engine = engine
    }

    public mutating func appendStep(_ title: String, detail: String = "") {
        steps.append(AgentStep(title: title, detail: detail))
    }

    public mutating func steer(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        steerMessages.append(trimmed)
        appendStep("Steered", detail: trimmed)
    }
}

public enum BackgroundAgentCoordinator {
    public static let moveThreshold: TimeInterval = 15

    public static func shouldMoveToBackground(started: Date, now: Date) -> Bool {
        now.timeIntervalSince(started) >= moveThreshold
    }

    public static func parseSteer(_ text: String) -> String? {
        var utterance = Utterance(text)
        utterance.stripFiller()
        let joined = utterance.words.joined(separator: " ")
        for prefix in ["tell the hub agent to ", "tell the agent to ", "steer agent to ", "steer: "] {
            if joined.hasPrefix(prefix) { return String(joined.dropFirst(prefix.count)) }
        }
        if joined.hasPrefix("steer ") { return String(joined.dropFirst("steer ".count)) }
        return nil
    }

    public static func holdCompletionWhileTyping(isTyping: Bool, finished: Date?) -> Bool {
        finished != nil && isTyping
    }
}
