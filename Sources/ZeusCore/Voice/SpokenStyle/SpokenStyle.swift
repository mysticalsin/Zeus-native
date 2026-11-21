import Foundation

/// Language of a spoken reply. The caller chooses it. Nothing here reads the system locale,
/// so the same input always produces the same words.
public enum SpokenLanguage: Sendable, Equatable, CaseIterable {
    case english
    case french
}

/// A break the speaker inserts. This is not SSML and not a provider string. Each voice
/// provider maps the case onto its own pause when it is wired up.
public enum SpokenPause: Sendable, Equatable, CaseIterable {
    /// A comma, semicolon, colon, or dash inside one sentence.
    case clause
    /// The end of a sentence.
    case sentence
}

/// One stretch of words and the pause that follows it.
public struct SpokenRun: Sendable, Equatable {
    public var text: String
    public var pauseAfter: SpokenPause

    public init(text: String, pauseAfter: SpokenPause) {
        self.text = text
        self.pauseAfter = pauseAfter
    }
}

/// The words a voice should speak, plus the pause after each stretch.
public struct SpokenTranscript: Sendable, Equatable {
    public var runs: [SpokenRun]
    /// `runs` joined by single spaces. Pause markers stay on `runs` and are not written in here.
    public var spokenText: String

    public init(runs: [SpokenRun], spokenText: String) {
        self.runs = runs
        self.spokenText = spokenText
    }
}

/// Text moving through the pipeline. Stages before `clauses` fill `text` and leave `runs` empty.
/// `clauses` fills `runs`. `answerFirst` drops runs past the sentence budget.
public struct SpokenDraft: Sendable, Equatable {
    public var text: String
    public var runs: [SpokenRun]

    public init(text: String, runs: [SpokenRun] = []) {
        self.text = text
        self.runs = runs
    }
}

/// One pure transformation. `order` is the pipeline. The switch in `transform` names every case
/// and has no default, so a new stage does not compile until it is placed.
public enum SpokenStage: Sendable, Equatable, CaseIterable {
    case markdown
    case links
    case quantities
    case contractions
    case clauses
    case answerFirst

    public static let order: [SpokenStage] = [
        .markdown,
        .links,
        .quantities,
        .contractions,
        .clauses,
        .answerFirst,
    ]

    public func transform(_ draft: SpokenDraft, language: SpokenLanguage, maxSentences: Int?) -> SpokenDraft {
        switch self {
        case .markdown:
            return SpokenMarkdown.apply(draft, language: language)
        case .links:
            return SpokenLinks.apply(draft, language: language)
        case .quantities:
            return SpokenQuantities.apply(draft, language: language)
        case .contractions:
            return SpokenContractions.apply(draft, language: language)
        case .clauses:
            return SpokenClauses.apply(draft)
        case .answerFirst:
            return SpokenAnswerFirst.apply(draft, maxSentences: maxSentences)
        }
    }
}

public struct SpokenRequest: Sendable, Equatable {
    public var text: String
    public var language: SpokenLanguage
    /// When set, only the first this many sentences are kept. `nil` keeps the whole reply.
    /// Zero or a negative budget keeps nothing.
    public var maxSentences: Int?

    public init(text: String, language: SpokenLanguage, maxSentences: Int? = nil) {
        self.text = text
        self.language = language
        self.maxSentences = maxSentences
    }
}

/// Pure text shaping for TTS. No clock, no locale, no provider, no audio.
public enum SpokenStyle {
    /// A sentence longer than this is split at a clause boundary into another sentence.
    public static let maxWordsPerSentence = 16

    public static let stages: [SpokenStage] = SpokenStage.order

    public static func transform(_ request: SpokenRequest) -> SpokenTranscript {
        var draft = SpokenDraft(text: request.text, runs: [])
        for stage in stages {
            draft = stage.transform(draft, language: request.language, maxSentences: request.maxSentences)
        }
        let spoken = SpokenText.collapse(draft.runs.map(\.text).joined(separator: " "))
        return SpokenTranscript(runs: draft.runs, spokenText: spoken)
    }
}
