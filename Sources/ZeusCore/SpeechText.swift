import Foundation

/// Cuts streamed text into sentences so speech can start before the reply is complete.
public struct SentenceSplitter: Sendable {
    private var buffer = ""
    private var spokeClause = false

    public init() {}

    public mutating func feed(_ text: String) -> [String] {
        buffer += text
        var sentences: [String] = []
        var start = buffer.startIndex
        var index = buffer.startIndex
        while index < buffer.endIndex {
            let character = buffer[index]
            let next = buffer.index(after: index)
            let endsSentence = ".!?…".contains(character) && next < buffer.endIndex && buffer[next].isWhitespace
            if endsSentence || character == "\n" {
                let sentence = buffer[start...index].trimmingCharacters(in: .whitespacesAndNewlines)
                if sentence.count > 1 { sentences.append(sentence) }
                start = next
            }
            index = next
        }
        buffer = String(buffer[start...])
        if !sentences.isEmpty { spokeClause = true }
        if !spokeClause {
            var early = takeEarlyClause()
            if early == nil { early = takeLongFirstWords() }
            if let early {
                sentences.append(early)
                spokeClause = true
            }
        }
        return sentences
    }

    /// The first comma or semicolon clause, so speech can start before the sentence ends.
    private mutating func takeEarlyClause() -> String? {
        guard let range = buffer.range(of: ", ") ?? buffer.range(of: "; ") else { return nil }
        let head = buffer[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard head.split(whereSeparator: \.isWhitespace).count >= 3 else { return nil }
        buffer = String(buffer[range.upperBound...])
        return head + ","
    }

    /// A long first sentence with no comma: speak its first `firstChunkWords` complete words so audio
    /// starts while the rest is still being written. Only a word followed by whitespace counts as complete.
    public static let firstChunkWords = 12

    private mutating func takeLongFirstWords() -> String? {
        var count = 0
        var index = buffer.startIndex
        var inWord = false
        while index < buffer.endIndex {
            let character = buffer[index]
            if character.isWhitespace {
                if inWord {
                    count += 1
                    inWord = false
                    if count == Self.firstChunkWords {
                        let head = buffer[..<index].trimmingCharacters(in: .whitespacesAndNewlines)
                        buffer = String(buffer[index...])
                        return head
                    }
                }
            } else {
                inWord = true
            }
            index = buffer.index(after: index)
        }
        return nil
    }

    /// Whatever is left once the reply has finished.
    public mutating func flush() -> String? {
        defer { buffer = "" }
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }
}

/// Maps a short spoken answer to an approval verdict ("ok", "no", "go ahead", "oui"…).
public enum ApprovalPhrases {
    static let allow = ["ok", "okay", "yes", "yeah", "yep", "sure", "approve", "approved", "allow", "go ahead",
                        "do it", "go for it", "accept", "oui", "vas-y", "d'accord"]
    static let deny = ["no", "nope", "deny", "denied", "stop", "don't", "do not", "cancel", "reject", "block", "non"]

    /// With your own keywords (Settings > Voice): `approve` replaces the built-in yes words, `deny` adds to
    /// the built-in no words (negatives always win), and `open` hands the request back to the agent's app (`.ask`).
    public static func verdict(for transcript: String, approve: [String], deny extraDeny: [String], open: [String]) -> HookDecision.Verdict? {
        let words = transcript.lowercased()
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'-")).inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= 6 else { return nil }
        let text = " " + words.joined(separator: " ") + " "
        func matches(_ phrases: [String]) -> Bool { phrases.contains { !$0.isEmpty && text.contains(" \($0) ") } }
        if matches(deny + extraDeny) { return .deny }
        if matches(open) { return .ask }
        if matches(approve.isEmpty ? allow : approve) { return .allow }
        return nil
    }

    public static func verdict(for transcript: String) -> HookDecision.Verdict? {
        let words = transcript.lowercased()
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'-")).inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= 6 else { return nil } // a long sentence is a question, not an answer
        let text = " " + words.joined(separator: " ") + " "
        func matches(_ phrases: [String]) -> Bool { phrases.contains { text.contains(" \($0) ") } }
        // Negatives win: "no, don't do it" must never approve.
        if matches(deny) { return .deny }
        if matches(allow) { return .allow }
        return nil
    }
}
