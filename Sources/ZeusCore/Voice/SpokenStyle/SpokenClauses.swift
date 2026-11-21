import Foundation

enum SpokenClauses {
    private static let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "st", "vs", "etc", "e.g", "i.e"]

    static func apply(_ draft: SpokenDraft) -> SpokenDraft {
        let text = SpokenText.collapse(draft.text)
        if text.isEmpty { return SpokenDraft(text: "", runs: []) }
        var runs: [SpokenRun] = []
        for sentence in sentences(in: text) {
            runs.append(contentsOf: runsForSentence(sentence))
        }
        let spoken = SpokenText.collapse(runs.map(\.text).joined(separator: " "))
        return SpokenDraft(text: spoken, runs: runs)
    }

    private static func sentences(in text: String) -> [String] {
        let chars = Array(text)
        var parts: [String] = []
        var start = 0
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if ".!?".contains(character) {
                let atEnd = index + 1 >= chars.count
                let boundary = atEnd || chars[index + 1].isWhitespace
                if boundary, !isAbbreviation(chars, period: index, start: start) {
                    let piece = String(chars[start...index]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !piece.isEmpty { parts.append(piece) }
                    var next = index + 1
                    while next < chars.count, chars[next].isWhitespace { next += 1 }
                    start = next
                    index = next
                    continue
                }
            }
            index += 1
        }
        if start < chars.count {
            let tail = String(chars[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { parts.append(tail) }
        }
        return parts
    }

    private static func isAbbreviation(_ chars: [Character], period: Int, start: Int) -> Bool {
        var wordStart = period
        while wordStart > start, !chars[wordStart - 1].isWhitespace {
            wordStart -= 1
        }
        var token = String(chars[wordStart..<period]).lowercased()
        while token.last == "." { token.removeLast() }
        return abbreviations.contains(token)
    }

    private static func runsForSentence(_ sentence: String) -> [SpokenRun] {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let mark: Character
        var body = trimmed
        if let last = body.last, ".!?".contains(last) {
            mark = last
            body.removeLast()
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            mark = "."
        }
        let pieces = clauses(in: body)
        if pieces.isEmpty { return [] }
        let groups = packed(pieces)
        var runs: [SpokenRun] = []
        for (groupIndex, group) in groups.enumerated() {
            let lastGroup = groupIndex == groups.count - 1
            for (clauseIndex, clause) in group.enumerated() {
                let lastClause = clauseIndex == group.count - 1
                if lastClause {
                    let ending: Character = lastGroup ? mark : "."
                    runs.append(SpokenRun(text: withEnding(ending, on: clause), pauseAfter: .sentence))
                } else {
                    runs.append(SpokenRun(text: clause, pauseAfter: .clause))
                }
            }
        }
        return runs
    }

    private static func clauses(in body: String) -> [String] {
        var parts: [String] = []
        var current = ""
        let characters = Array(body)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "," || character == ";" || character == ":" || character == "\u{2014}" || character == "\u{2013}" {
                append(current, to: &parts)
                current = ""
                index += 1
                continue
            }
            if character == "-", index + 1 < characters.count, characters[index + 1] == " ", current.last == " " {
                append(current, to: &parts)
                current = ""
                index += 2
                continue
            }
            current.append(character)
            index += 1
        }
        append(current, to: &parts)
        return parts
    }

    private static func append(_ text: String, to parts: inout [String]) {
        let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !piece.isEmpty { parts.append(piece) }
    }

    /// Clauses stay in one sentence until the next one would pass the word budget. The clause
    /// that does not fit starts a new sentence.
    private static func packed(_ clauses: [String]) -> [[String]] {
        var groups: [[String]] = []
        var current: [String] = []
        var count = 0
        for clause in clauses {
            let words = SpokenText.words(in: clause)
            if !current.isEmpty, count + words > SpokenStyle.maxWordsPerSentence {
                groups.append(current)
                current = [SpokenText.capitalizingFirst(clause)]
                count = words
            } else {
                current.append(clause)
                count += words
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    private static func withEnding(_ ending: Character, on clause: String) -> String {
        if let last = clause.last, ".!?".contains(last) { return clause }
        return clause + String(ending)
    }
}
