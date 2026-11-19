import Foundation

/// Where a speaker's name came from, strongest first.
public enum ScribeNameSource: String, Codable, Sendable, CaseIterable {
    case manual, savedVoice, callWindow, calendar, introduction

    /// Higher outranks lower when two automatic sources disagree.
    public var rank: Int {
        switch self {
        case .manual: return 5
        case .savedVoice: return 4
        case .callWindow: return 3
        case .calendar: return 2
        case .introduction: return 1
        }
    }

    /// Short words for the recap ("from the call"), no punctuation tricks.
    public var caption: String {
        switch self {
        case .manual: return "you typed this"
        case .savedVoice: return "saved voice"
        case .callWindow: return "from the call"
        case .calendar: return "from the invite"
        case .introduction: return "from what they said"
        }
    }
}

/// What Zeus knows about one named speaker of one meeting. Saved with the meeting.
public struct ScribeSpeakerIdentity: Codable, Equatable, Sendable {
    /// The name now on the speaker's lines.
    public var name: String
    /// The diarizer's own label before the name, such as "Speaker 2".
    public var originalLabel: String
    public var source: ScribeNameSource
    /// 0...1. Typed names are 1.
    public var confidence: Double
    /// The person accepted or typed this name: nothing automatic may change it.
    public var confirmed: Bool

    public init(name: String, originalLabel: String, source: ScribeNameSource, confidence: Double, confirmed: Bool) {
        self.name = name
        self.originalLabel = originalLabel
        self.source = source
        self.confidence = confidence
        self.confirmed = confirmed
    }

    /// An automatic name under this confidence shows as unconfirmed in the recap.
    public static let confidentEnough = 0.8
    public var needsConfirmation: Bool { !confirmed && confidence < Self.confidentEnough }
}

/// A name the person said no to for one voice.
public struct ScribeDeclinedName: Codable, Equatable, Sendable {
    public var label: String
    public var nameKey: String

    public init(label: String, nameKey: String) {
        self.label = label
        self.nameKey = nameKey
    }
}

/// One block of lines folded into another speaker when tiny voices were pruned.
public struct ScribeSpeakerFold: Codable, Equatable, Sendable {
    public var segmentID: String
    public var from: ScribeSpeakerRecordLabel
    public var into: ScribeSpeakerRecordLabel

    public init(segmentID: String, from: ScribeSpeakerRecordLabel, into: ScribeSpeakerRecordLabel) {
        self.segmentID = segmentID
        self.from = from
        self.into = into
    }
}

/// A speaker as saved: the same encoding as a transcript line.
public struct ScribeSpeakerRecordLabel: Codable, Equatable, Sendable {
    public var kind: String
    public var label: String?

    public init(_ speaker: ScribeSpeaker) {
        switch speaker {
        case .you: kind = "you"; label = nil
        case .participant(let name): kind = "participant"; label = name
        case .unknown: kind = "unknown"; label = nil
        }
    }

    public var speaker: ScribeSpeaker {
        switch kind {
        case "you": return .you
        case "participant": return .participant(label ?? "Speaker")
        default: return .unknown
        }
    }
}

/// The names of one meeting's speakers, with where each came from. Pure value, persisted with the meeting.
/// Rules: a typed or accepted name always wins and no automatic evidence changes it; an automatic name is replaced
/// only by clearly stronger evidence; a name the person declined is never offered again for that voice.
public struct ScribeSpeakerBook: Codable, Equatable, Sendable {
    public private(set) var identities: [ScribeSpeakerIdentity] = []
    public private(set) var declined: [ScribeDeclinedName] = []
    public private(set) var folds: [ScribeSpeakerFold] = []

    public init() {}

    public enum BindResult: Equatable, Sendable {
        case bound
        case unchanged
        case keptManual
        case declined
        case weaker
    }

    /// A later automatic name has to beat the earlier one by this much confidence to replace it.
    public static let correctionMargin = 0.1

    public func identity(named name: String) -> ScribeSpeakerIdentity? {
        let key = speakerNameKey(name)
        return identities.first { speakerNameKey($0.name) == key }
    }

    public func identity(forOriginal label: String) -> ScribeSpeakerIdentity? {
        identities.first { $0.originalLabel == label }
    }

    public func isDeclined(_ name: String, for label: String) -> Bool {
        let key = speakerNameKey(name)
        return declined.contains { $0.label == label && $0.nameKey == key }
    }

    public var confirmedNameKeys: Set<String> {
        Set(identities.filter(\.confirmed).map { speakerNameKey($0.name) })
    }

    /// Offers an automatic name for the voice the diarizer calls `label`.
    @discardableResult
    public mutating func bindAutomatic(
        label: String, name: String, source: ScribeNameSource, confidence: Double
    ) -> BindResult {
        guard source != .manual else { return .unchanged }  // typed names go through setConfirmed
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return .unchanged }
        if isDeclined(clean, for: label) { return .declined }
        let value = min(1, max(0, confidence))
        if let index = identities.firstIndex(where: { $0.originalLabel == label }) {
            let old = identities[index]
            if old.confirmed { return .keptManual }
            if speakerNameKey(old.name) == speakerNameKey(clean) {
                guard value > old.confidence || source.rank > old.source.rank else { return .unchanged }
                identities[index].confidence = max(old.confidence, value)
                if source.rank > old.source.rank { identities[index].source = source }
                return .bound
            }
            // Different name: only clearly stronger evidence corrects an automatic one.
            let stronger = source.rank > old.source.rank || value >= old.confidence + Self.correctionMargin
            guard stronger else { return .weaker }
            identities[index] = ScribeSpeakerIdentity(
                name: clean, originalLabel: label, source: source, confidence: value, confirmed: false
            )
            return .bound
        }
        // Another voice already holds this confirmed name: a typed name is never taken away.
        if confirmedNameKeys.contains(speakerNameKey(clean)) { return .keptManual }
        identities.append(ScribeSpeakerIdentity(
            name: clean, originalLabel: label, source: source, confidence: value, confirmed: false
        ))
        return .bound
    }

    /// The person typed a name (or accepted a suggestion, `source` then says where it came from).
    public mutating func setConfirmed(
        label: String, name: String, source: ScribeNameSource = .manual, confidence: Double = 1
    ) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        identities.removeAll { $0.originalLabel == label }
        // Two voices given one name are one person: keep a single identity for it.
        if let same = identities.firstIndex(where: { speakerNameKey($0.name) == speakerNameKey(clean) }) {
            identities[same].confirmed = true
            if source == .manual { identities[same].source = .manual; identities[same].confidence = 1 }
            return
        }
        identities.append(ScribeSpeakerIdentity(
            name: clean, originalLabel: label, source: source, confidence: source == .manual ? 1 : confidence, confirmed: true
        ))
    }

    /// "Not them": forget the name and never offer it again for that voice. Returns the label to put back.
    @discardableResult
    public mutating func decline(name: String) -> String? {
        guard let index = identities.firstIndex(where: { speakerNameKey($0.name) == speakerNameKey(name) }) else {
            return nil
        }
        let old = identities.remove(at: index)
        declined.append(ScribeDeclinedName(label: old.originalLabel, nameKey: speakerNameKey(old.name)))
        return old.originalLabel
    }

    /// A speaker was renamed in the transcript: keep the identity's name in step.
    public mutating func renamed(from old: String, to new: String) {
        let oldKey = speakerNameKey(old)
        guard let index = identities.firstIndex(where: { speakerNameKey($0.name) == oldKey }) else { return }
        identities[index].name = new
    }

    /// Drops identities whose name no longer labels any line.
    public mutating func keepOnly(namesIn segments: [ScribeTranscriptSegment]) {
        var used: Set<String> = []
        for segment in segments { if case .participant(let name) = segment.speaker { used.insert(speakerNameKey(name)) } }
        identities.removeAll { !used.contains(speakerNameKey($0.name)) }
    }

    /// Forgets every name nobody confirmed (the voices underneath were re-read, so they must be named again).
    public mutating func removeUnconfirmed() { identities.removeAll { !$0.confirmed } }

    public mutating func recordFolds(_ new: [ScribeSpeakerFold]) { folds.append(contentsOf: new) }
    public mutating func clearFolds() { folds = [] }
}

/// Case, accent and spacing differences do not make two names two people (same folding as `ScribeAttendeeNames.key`;
/// kept here so this file stands alone in the portable excerpts).
func speakerNameKey(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
}
