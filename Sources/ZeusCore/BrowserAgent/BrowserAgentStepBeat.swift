import Foundation

/// What the spark and the voice do for one browser-agent step.
///
/// The notch card already names the step. A real step is also spoken, and the spark keeps a
/// short line while that step runs. Looking at the page is shown, not spoken. Waiting for
/// approval is shown as "Needs you" and is not spoken again, because the approval card already speaks.
public struct BrowserAgentStepBeat: Equatable, Sendable {
    public static let boltLimit = 40

    public var spoken: String?
    public var bolt: String

    public init(spoken: String?, bolt: String) {
        self.spoken = spoken
        self.bolt = bolt
    }

    public enum Kind: Equatable, Sendable {
        case look
        case waiting
        case step
    }

    public static func kind(of action: String) -> Kind {
        let text = action.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "Looking at the page" { return .look }
        if text.hasPrefix("Waiting for your OK") { return .waiting }
        return .step
    }

    public static func make(step: Int, maxSteps: Int, action: String) -> BrowserAgentStepBeat {
        switch kind(of: action) {
        case .look:
            let text = action.trimmingCharacters(in: .whitespacesAndNewlines)
            return BrowserAgentStepBeat(spoken: nil, bolt: text.isEmpty ? "Here" : "Looking")
        case .waiting:
            return BrowserAgentStepBeat(spoken: nil, bolt: "Needs you")
        case .step:
            let number = max(step, 1)
            let total = max(maxSteps, number)
            return BrowserAgentStepBeat(spoken: "Step \(number) of \(total). \(sentence(action))", bolt: boltLine(action))
        }
    }

    private static func sentence(_ action: String) -> String {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return trimmed }
        if last == "." || last == "?" || last == "!" { return trimmed }
        return trimmed + "."
    }

    /// One spark line, at most 40 characters, cut on a word when the action is longer.
    private static func boltLine(_ raw: String) -> String {
        var current = ""
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > boltLimit { break }
            current = next
        }
        let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty { return line }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Here" }
        return String(trimmed.prefix(boltLimit))
    }
}
