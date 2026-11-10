import Foundation

public struct ScribeActionItem: Equatable, Sendable {
    public var text: String
    public var done: Bool

    public init(text: String, done: Bool = false) {
        self.text = text
        self.done = done
    }
}

public enum ScribeNotesMethod: Equatable, Sendable {
    /// Keyword line extraction. Deterministic and not AI.
    case extractive
}

public struct ScribeGeneratedNotes: Equatable, Sendable {
    public var summary: String
    public var decisions: [String]
    public var actionItems: [ScribeActionItem]
    public var generatedAt: Date
    public var method: ScribeNotesMethod

    public init(
        summary: String,
        decisions: [String],
        actionItems: [ScribeActionItem],
        generatedAt: Date,
        method: ScribeNotesMethod
    ) {
        self.summary = summary
        self.decisions = decisions
        self.actionItems = actionItems
        self.generatedAt = generatedAt
        self.method = method
    }

    public var isEmpty: Bool { summary.isEmpty && decisions.isEmpty && actionItems.isEmpty }
}

public struct ScribeMeetingNotes: Equatable, Sendable {
    public var summary: String
    public var decisions: [String]
    public var actionItems: [ScribeActionItem]
    /// Authored by the user. Generation never touches it.
    public var privateNotes: String
    public var generatedAt: Date?
    public var method: ScribeNotesMethod?

    public init(
        summary: String = "",
        decisions: [String] = [],
        actionItems: [ScribeActionItem] = [],
        privateNotes: String = "",
        generatedAt: Date? = nil,
        method: ScribeNotesMethod? = nil
    ) {
        self.summary = summary
        self.decisions = decisions
        self.actionItems = actionItems
        self.privateNotes = privateNotes
        self.generatedAt = generatedAt
        self.method = method
    }
}

public protocol ScribeNotesGenerator: Sendable {
    func generate(from transcript: ScribeTranscript) throws -> ScribeGeneratedNotes
}

public enum ScribeNotes {
    /// Replaces generated fields, keeps `privateNotes` byte-identical, and keeps the `done` flag
    /// of an action item whose text is unchanged.
    public static func merge(generated: ScribeGeneratedNotes, into existing: ScribeMeetingNotes) -> ScribeMeetingNotes {
        let doneTexts = Set(existing.actionItems.filter(\.done).map(\.text))
        let items = generated.actionItems.map { item in
            ScribeActionItem(text: item.text, done: item.done || doneTexts.contains(item.text))
        }
        return ScribeMeetingNotes(
            summary: generated.summary,
            decisions: generated.decisions,
            actionItems: items,
            privateNotes: existing.privateNotes,
            generatedAt: generated.generatedAt,
            method: generated.method
        )
    }
}

/// Deterministic keyword extraction over final segments. Labelled `.extractive`; it is not AI.
public struct ScribeExtractiveNotesGenerator: ScribeNotesGenerator {
    public static let decisionKeywords: Set<String> = ["decide", "decided", "decision", "agree", "agreed"]
    public static let actionKeywords: Set<String> = ["will", "todo", "action"]

    public let summaryLineCount: Int
    private let clock: @Sendable () -> Date

    public init(summaryLineCount: Int = 3, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.summaryLineCount = max(0, summaryLineCount)
        self.clock = clock
    }

    public func generate(from transcript: ScribeTranscript) throws -> ScribeGeneratedNotes {
        let lines = transcript.finalSegments
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var decisions: [String] = []
        var actions: [ScribeActionItem] = []
        for line in lines {
            let words = Set(line.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            if !words.isDisjoint(with: Self.decisionKeywords) {
                decisions.append(line)
            }
            if !words.isDisjoint(with: Self.actionKeywords) {
                actions.append(ScribeActionItem(text: line, done: false))
            }
        }

        return ScribeGeneratedNotes(
            summary: lines.prefix(summaryLineCount).joined(separator: " "),
            decisions: decisions,
            actionItems: actions,
            generatedAt: clock(),
            method: .extractive
        )
    }
}
