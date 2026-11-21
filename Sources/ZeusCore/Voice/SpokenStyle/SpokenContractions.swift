import Foundation

enum SpokenContractions {
    /// Longer phrases come first so "will not" is seen before any shorter overlap.
    private static let pairs: [(String, String)] = [
        ("will not", "won't"),
        ("cannot", "can't"),
        ("do not", "don't"),
        ("does not", "doesn't"),
        ("did not", "didn't"),
        ("is not", "isn't"),
        ("are not", "aren't"),
        ("was not", "wasn't"),
        ("were not", "weren't"),
        ("have not", "haven't"),
        ("has not", "hasn't"),
        ("had not", "hadn't"),
        ("would not", "wouldn't"),
        ("should not", "shouldn't"),
        ("could not", "couldn't"),
        ("i will", "i'll"),
        ("i have", "i've"),
        ("i would", "i'd"),
        ("i am", "i'm"),
        ("you are", "you're"),
        ("you will", "you'll"),
        ("you have", "you've"),
        ("we are", "we're"),
        ("we will", "we'll"),
        ("we have", "we've"),
        ("they are", "they're"),
        ("they will", "they'll"),
        ("they have", "they've"),
        ("it will", "it'll"),
        ("it is", "it's"),
        ("that is", "that's"),
        ("there is", "there's"),
        ("here is", "here's"),
        ("what is", "what's"),
        ("let us", "let's"),
    ]

    static func apply(_ draft: SpokenDraft, language: SpokenLanguage) -> SpokenDraft {
        switch language {
        case .english:
            return SpokenDraft(text: contracting(draft.text), runs: [])
        case .french:
            return SpokenDraft(text: draft.text, runs: [])
        }
    }

    private static func contracting(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if let hit = match(text, at: index) {
                result += hit.replacement
                index = text.index(index, offsetBy: hit.characters)
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return result
    }

    private static func match(_ text: String, at index: String.Index) -> (characters: Int, replacement: String)? {
        if index > text.startIndex, text[text.index(before: index)].isLetter { return nil }
        for (source, replacement) in pairs {
            // `count` on the tail is linear, and doing it at every word makes a long reply quadratic.
            guard let end = text.index(index, offsetBy: source.count, limitedBy: text.endIndex) else { continue }
            let slice = text[index..<end]
            guard String(slice).compare(source, options: .caseInsensitive) == .orderedSame else { continue }
            if end < text.endIndex, text[end].isLetter { continue }
            guard let spoken = cased(String(slice), template: replacement) else { continue }
            return (source.count, spoken)
        }
        return nil
    }

    /// All-capital phrases stay as written. A leading capital becomes a leading capital
    /// on the contraction ("It is" becomes "It's").
    private static func cased(_ source: String, template: String) -> String? {
        let letters = source.filter(\.isLetter)
        if !letters.isEmpty, letters.allSatisfy(\.isUppercase), letters.count > 1 { return nil }
        guard let first = template.first else { return template }
        if source.first?.isUppercase == true {
            return String(first).uppercased() + template.dropFirst()
        }
        return template
    }
}
