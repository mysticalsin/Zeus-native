import Foundation

/// Sorts one spoken question before a model call.
///
/// "Where is the button" and "walk me through this" set the guide flag and
/// leave web search off. A question that needs a fact from after the model's
/// knowledge year may turn web search on. The caller passes that year in.
/// Sorting never opens a connection, and the result is not applied to the
/// pointing session or the provider list. A blank is read from `QuestionSortBox`.
public struct QuestionSort: Equatable, Sendable {
    public let guides: Bool
    public let webSearch: Bool

    /// A spoken question longer than this, after spacing is collapsed, stays unsorted.
    public static let maximumCharacters = 280

    /// A named year is compared only when the cutoff sits in this closed range.
    public static let minimumKnowledgeYear = 1990
    public static let maximumKnowledgeYear = 2099

    public init(guides: Bool, webSearch: Bool) {
        self.guides = guides
        self.webSearch = webSearch
    }

    public static func sort(_ question: String, knowledgeThrough year: Int) -> QuestionSort {
        let text = normalize(question)
        guard !text.isEmpty, text.count <= maximumCharacters else {
            return QuestionSort(guides: false, webSearch: false)
        }
        if isGuide(text) {
            return QuestionSort(guides: true, webSearch: false)
        }
        if asksForLaterFact(text, knowledgeThrough: year) {
            return QuestionSort(guides: false, webSearch: true)
        }
        return QuestionSort(guides: false, webSearch: false)
    }

    private static let walkTimeTails = [
        "week", "weeks", "month", "months", "year", "years", "morning", "evening", "weekend",
    ]

    private static let laterPhrases = [
        "today", "todays", "latest", "right now", "just announced",
        "this week", "this weeks", "this month", "this months", "this year", "this years",
    ]

    private static func isGuide(_ text: String) -> Bool {
        if isWalkGuide(text) { return true }
        if containsPhrase(text, "what do i click") { return true }
        let asksWhere = containsPhrase(text, "where is") || containsPhrase(text, "wheres")
        return asksWhere && containsPhrase(text, "button")
    }

    /// "Walk me through this" is the guide sentence. "Walk me through this week"
    /// is a time span, so the word "this" stays with the week.
    private static func isWalkGuide(_ text: String) -> Bool {
        let phrase = "walk me through this"
        var rest = Substring(text)
        while let range = rest.range(of: phrase, options: .literal) {
            let beforeOK = range.lowerBound == rest.startIndex
                || isBlank(rest[rest.index(before: range.lowerBound)])
            let after = range.upperBound
            let afterOK = after == rest.endIndex || isBlank(rest[after])
            if beforeOK && afterOK {
                let next = rest[after...].drop(while: isBlank).prefix { !isBlank($0) }
                if next.isEmpty || !walkTimeTails.contains(String(next)) { return true }
            }
            guard let step = rest.index(range.lowerBound, offsetBy: 1, limitedBy: rest.endIndex),
                  step < rest.endIndex else { return false }
            rest = rest[step...]
        }
        return false
    }

    private static func asksForLaterFact(_ text: String, knowledgeThrough year: Int) -> Bool {
        if laterPhrases.contains(where: { containsPhrase(text, $0) }) { return true }
        guard (minimumKnowledgeYear...maximumKnowledgeYear).contains(year) else { return false }
        return years(in: text).contains { $0 > year }
    }

    private static func containsPhrase(_ text: String, _ phrase: String) -> Bool {
        guard !phrase.isEmpty else { return false }
        var rest = Substring(text)
        while let range = rest.range(of: phrase, options: .literal) {
            let beforeOK = range.lowerBound == rest.startIndex
                || isBlank(rest[rest.index(before: range.lowerBound)])
            let after = range.upperBound
            let afterOK = after == rest.endIndex || isBlank(rest[after])
            if beforeOK && afterOK { return true }
            guard let step = rest.index(range.lowerBound, offsetBy: 1, limitedBy: rest.endIndex),
                  step < rest.endIndex else { return false }
            rest = rest[step...]
        }
        return false
    }

    /// Four-digit years from 1900 through 2099. A year glued to a letter is not a year.
    private static func years(in text: String) -> [Int] {
        var found: [Int] = []
        var digits = ""
        var startedAfterLetter = false
        var previousWasLetter = false

        func flush(followedByLetter: Bool) {
            if digits.count == 4, !startedAfterLetter, !followedByLetter,
               let year = Int(digits), (1900...2099).contains(year) {
                found.append(year)
            }
            digits = ""
            startedAfterLetter = false
        }

        for character in text {
            if character.isNumber {
                if digits.isEmpty { startedAfterLetter = previousWasLetter }
                digits.append(character)
                previousWasLetter = false
            } else {
                flush(followedByLetter: character.isLetter)
                previousWasLetter = character.isLetter
            }
        }
        flush(followedByLetter: false)
        return found
    }

    private static func normalize(_ question: String) -> String {
        var out = ""
        out.reserveCapacity(question.count)
        var pendingSpace = false
        for character in question {
            if isApostrophe(character) { continue }
            if isSeparator(character) {
                pendingSpace = !out.isEmpty
                continue
            }
            if pendingSpace {
                out.append(" ")
                pendingSpace = false
            }
            out.append(contentsOf: character.lowercased())
        }
        return out
    }

    private static func isApostrophe(_ character: Character) -> Bool {
        guard let value = singleScalar(character) else { return false }
        switch value {
        case 0x27, 0x2018, 0x2019, 0x02BC: return true
        default: return false
        }
    }

    private static func isBlank(_ character: Character) -> Bool {
        QuestionSortBox.isBlank(String(character))
    }

    private static func isSeparator(_ character: Character) -> Bool {
        if isBlank(character) { return true }
        if "?!.,;:\"()[]".contains(character) { return true }
        guard let value = singleScalar(character) else { return false }
        switch value {
        case 0x2013, 0x2014, 0x2026, 0x201C, 0x201D: return true
        default: return false
        }
    }

    private static func singleScalar(_ character: Character) -> UInt32? {
        guard character.unicodeScalars.count == 1 else { return nil }
        return character.unicodeScalars.first?.value
    }
}
