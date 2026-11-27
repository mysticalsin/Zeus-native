import Foundation

/// A spoken "point at" or "show me" that becomes one guidance proposal.
/// The allowlist runs before anything is shown. This path never builds an open, insert,
/// clipboard, or link draft, and it does not read model tool calls.
public enum SpokenPointingAsk {
    public struct Show: Equatable, Sendable {
        public var spoken: String
        public var bolt: String
        public var targetID: String

        public init(spoken: String, bolt: String, targetID: String) {
            self.spoken = spoken
            self.bolt = bolt
            self.targetID = targetID
        }
    }

    /// True when the words ask to point at something on screen.
    public static func isAsk(_ utterance: String) -> Bool {
        askedLabel(in: utterance) != nil
    }

    /// The guide to draw, after the allowlist admits one click target. Nil when the words
    /// are not a point, the target is missing or secure, or the gate refuses.
    public static func show(in utterance: String, candidates: [PointingProposalCandidate]) -> Show? {
        guard let ask = askedLabel(in: utterance) else { return nil }
        guard let match = best(ask.phrase, in: candidates) else { return nil }
        let name = match.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let summary = String("\(ask.verb) \(name)".prefix(160))
        let draft = PointingProposalDraft(
            id: "spoken-point",
            kind: "guidance",
            tool: "awaitClick",
            targetID: match.id,
            arguments: [:],
            summary: summary
        )
        let decisions = PointingProposalGate.decide(
            [draft], candidates: candidates, focusedFieldIsSecure: false, admittedThisTurn: 0)
        guard decisions.count == 1, case .guide(let proposal) = decisions[0],
              proposal.tool == .awaitClick, proposal.targetID == match.id else { return nil }
        let bolt = PointerGuideCaptionSplit.oneLine(summary)
            ?? PointerGuideCaptionSplit.boltText(name)
            ?? "Here"
        guard PointerGuideCaptionSplit.boltText(bolt) == bolt else { return nil }
        return Show(spoken: "\(name) is right here.", bolt: bolt, targetID: match.id)
    }

    private static let leads: [(prefix: String, verb: String)] = [
        ("point at ", "Point at"),
        ("point to ", "Point at"),
        ("point out ", "Point at"),
        ("show me where ", "Point at"),
        ("show me ", "Point at"),
        ("highlight ", "Highlight"),
        ("outline ", "Outline"),
        ("where is ", "Point at"),
        ("where s ", "Point at"),
    ]

    private static func askedLabel(in utterance: String) -> (verb: String, phrase: String)? {
        let raw = utterance.lowercased()
        if raw.contains("://") || raw.contains("javascript:") || raw.contains("data:") || raw.contains("file:") {
            return nil
        }
        let key = normalized(utterance)
        guard !key.isEmpty else { return nil }
        for lead in leads where key.hasPrefix(lead.prefix) {
            var rest = String(key.dropFirst(lead.prefix.count))
            if rest.hasPrefix("how ") || rest == "how" { return nil }
            var words = rest.split(separator: " ").map(String.init)
            while let first = words.first, ["the", "a", "an"].contains(first) { words.removeFirst() }
            rest = words.joined(separator: " ")
            guard !rest.isEmpty, rest.count <= 80 else { return nil }
            return (lead.verb, rest)
        }
        return nil
    }

    private static func best(_ phrase: String, in candidates: [PointingProposalCandidate]) -> PointingProposalCandidate? {
        let need = tokens(phrase)
        guard !need.isEmpty else { return nil }
        let exact = candidates.filter { candidate in
            let name = candidate.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && tokens(name) == need
        }
        if exact.contains(where: { $0.isSecure || isBareSecret($0.label) }) { return nil }
        let matches = candidates.filter { candidate in
            guard !candidate.isSecure else { return false }
            let name = candidate.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return false }
            let words = tokens(name)
            return words == need || contains(words, phrase: need)
        }
        return matches.sorted { a, b in
            let aExact = tokens(a.label) == need
            let bExact = tokens(b.label) == need
            if aExact != bExact { return aExact }
            if a.label.count != b.label.count { return a.label.count < b.label.count }
            return false
        }.first
    }

    /// A label that is only a secret word or a secret phrase. A longer control such as
    /// "Change password" is not this, so a point at that button can still land.
    private static func isBareSecret(_ label: String) -> Bool {
        let words = tokens(label)
        let phrase = words.joined(separator: " ")
        if DriveStep.secretPhrases.contains(phrase) { return true }
        return !words.isEmpty && words.allSatisfy { DriveStep.secretWords.contains($0) }
    }

    private static func contains(_ words: [String], phrase: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }
        for start in 0...(words.count - phrase.count) {
            if Array(words[start..<(start + phrase.count)]) == phrase { return true }
        }
        return false
    }

    private static func normalized(_ text: String) -> String {
        tokens(text).joined(separator: " ")
    }

    private static func tokens(_ text: String) -> [String] {
        let folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        let spaced = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(spaced).split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
