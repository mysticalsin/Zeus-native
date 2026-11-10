import Foundation

/// A spoken or typed request cut into words, with each word kept twice: as said (for to-do titles
/// and search queries, which keep their case) and normalised for matching (lower case, accents
/// folded, "to-do" / "to do" / "todo" made one word, French elisions split: "l'écran" → "l'" "ecran").
public struct Utterance: Equatable, Sendable {
    /// Words as said, outer punctuation trimmed.
    public private(set) var original: [String]
    /// Normalised words, same count and order as `original`.
    public private(set) var words: [String]
    /// The trimmed source text and, per word, where it sits in it (to recover "a, b and c" with its commas).
    public let text: String
    private var spans: [Range<String.Index>]

    public init(_ raw: String) {
        let cleaned = raw.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
        text = cleaned
        var original: [String] = [], words: [String] = [], spans: [Range<String.Index>] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            while index < cleaned.endIndex, cleaned[index].isWhitespace { index = cleaned.index(after: index) }
            guard index < cleaned.endIndex else { break }
            var end = index
            while end < cleaned.endIndex, !cleaned[end].isWhitespace { end = cleaned.index(after: end) }
            var lower = index, upper = end
            while lower < upper, Self.trimmable(cleaned[lower]) { lower = cleaned.index(after: lower) }
            while upper > lower, Self.trimmable(cleaned[cleaned.index(before: upper)]) { upper = cleaned.index(before: upper) }
            if lower < upper {
                let token = String(cleaned[lower..<upper])
                let norm = Self.normalize(token)
                // French elision: "l'ecran" → "l'" + "ecran", "d'appeler" → "d'" + "appeler".
                if let quote = norm.firstIndex(of: "'"), norm.distance(from: norm.startIndex, to: quote) <= 2,
                   Self.elisions.contains(String(norm[...quote])), norm.index(after: quote) < norm.endIndex,
                   let cut = token.firstIndex(of: "'") {
                    let split = token.index(after: cut)
                    original.append(String(token[..<split])); words.append(String(norm[...quote])); spans.append(lower..<cleaned.index(lower, offsetBy: token.distance(from: token.startIndex, to: split)))
                    original.append(String(token[split...])); words.append(String(norm[norm.index(after: quote)...])); spans.append(cleaned.index(lower, offsetBy: token.distance(from: token.startIndex, to: split))..<upper)
                } else {
                    original.append(token); words.append(norm); spans.append(lower..<upper)
                }
            }
            index = end
        }
        self.original = original
        self.words = words
        self.spans = spans
        mergeToDo()
    }

    private static let elisions: Set<String> = ["l'", "d'", "j'", "m'", "t'", "s'", "n'", "qu'", "c'"]

    private static func trimmable(_ c: Character) -> Bool {
        c != "%" && (c.isPunctuation || c.isSymbol)
    }

    public static func normalize(_ token: String) -> String {
        var word = token.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
        if word.hasSuffix("'s"), word.count > 3, word != "let's" { word = String(word.dropLast(2)) }
        switch word {
        case "to-do", "todo", "to-dos", "todos": return word.hasSuffix("s") ? "todos" : "todo"
        case "ok": return "okay"
        default: return word
        }
    }

    /// "to do" after "my", "the", "a", "new", "add" or at the start is the noun "to-do".
    private mutating func mergeToDo() {
        var i = 0
        while i + 1 < words.count {
            if words[i] == "to", words[i + 1] == "do" || words[i + 1] == "dos",
               i == 0 || ["my", "the", "a", "new", "add", "your"].contains(words[i - 1]) {
                let plural = words[i + 1] == "dos"
                words.replaceSubrange(i...(i + 1), with: [plural ? "todos" : "todo"])
                original.replaceSubrange(i...(i + 1), with: [original[i] + " " + original[i + 1]])
                spans.replaceSubrange(i...(i + 1), with: [spans[i].lowerBound..<spans[i + 1].upperBound])
            }
            i += 1
        }
    }

    public var isEmpty: Bool { words.isEmpty }
    public var count: Int { words.count }

    /// Drops words from the front and back, keeping both arrays in step.
    public mutating func drop(first n: Int) {
        let n = min(n, words.count)
        words.removeFirst(n); original.removeFirst(n); spans.removeFirst(n)
    }

    public mutating func drop(last n: Int) {
        let n = min(n, words.count)
        words.removeLast(n); original.removeLast(n); spans.removeLast(n)
    }

    /// The words in `range` as said, joined by single spaces.
    public func said(_ range: Range<Int>) -> String {
        original[range].joined(separator: " ")
    }

    /// The source text between the first and last word of `range`, punctuation inside kept ("a, b and c").
    public func source(_ range: Range<Int>) -> String {
        guard !range.isEmpty else { return "" }
        return String(text[spans[range.lowerBound].lowerBound..<spans[range.upperBound - 1].upperBound])
    }

    public func hasPrefix(_ phrase: [String]) -> Bool {
        phrase.count <= words.count && Array(words.prefix(phrase.count)) == phrase
    }

    public func hasSuffix(_ phrase: [String]) -> Bool {
        phrase.count <= words.count && Array(words.suffix(phrase.count)) == phrase
    }

    // MARK: Filler

    /// Leading phrases that carry no meaning for a command: "please", "can you", "could you",
    /// "hey", "so", "um", and their French and Portuguese twins. Wake phrases are removed first.
    static let leadingFiller: [[String]] = [
        "i want you to", "i'd like you to", "i would like you to", "i need you to", "would you please", "could you please",
        "can you please", "will you please", "can you", "could you", "would you", "will you", "go ahead and", "please",
        "just", "quickly", "um", "uh", "umm", "erm", "so", "okay", "alright", "all right", "now", "hey", "yo", "zeus",
        "est-ce que tu peux", "est-ce que vous pouvez", "tu peux", "peux-tu", "pouvez-vous", "vous pouvez", "s' il te plait", "s' il vous plait", "alors", "bon",
        "voce pode", "voce poderia", "pode", "poderia", "por favor", "entao", "e ai",
    ].map { $0.split(separator: " ").map(String.init) }

    static let trailingFiller: [[String]] = [
        "please", "for me", "right now", "now", "thanks", "thank you", "thank you very much", "zeus", "okay",
        "s' il te plait", "s' il vous plait", "pour moi", "merci", "por favor", "pra mim", "para mim", "obrigado", "obrigada", "agora",
    ].map { $0.split(separator: " ").map(String.init) }

    /// Words that, right before "zeus", make it a name ("in zeus", "open zeus", "the zeus").
    static let namesAThing: Set<String> = [
        "in", "on", "at", "into", "inside", "for", "to", "with", "of", "from", "the", "my", "open", "launch", "start", "switch", "go",
        "dans", "sur", "pour", "le", "la", "mon", "ma", "ouvre", "lance", "no", "na", "em", "para", "do", "da", "o", "a", "meu", "minha", "abre",
    ]

    /// Removes a wake phrase ("hey zeus") and filler from both ends, repeatedly.
    public mutating func stripFiller() {
        if let wake = WakePhrase.prefixLength(words) { drop(first: wake) }
        var changed = true
        while changed, !words.isEmpty {
            changed = false
            for phrase in Self.leadingFiller where hasPrefix(phrase) && phrase.count < words.count {
                drop(first: phrase.count); changed = true; break
            }
            for phrase in Self.trailingFiller where hasSuffix(phrase) && phrase.count < words.count {
                // "fix the bug in zeus": here Zeus is the project, not Tony addressing the assistant.
                if phrase == ["zeus"], Self.namesAThing.contains(words[words.count - 2]) { continue }
                drop(last: phrase.count); changed = true; break
            }
        }
    }
}
