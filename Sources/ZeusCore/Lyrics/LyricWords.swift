import Foundation

/// One word of a lyric line with the estimated seconds it starts and ends being sung.
/// `text` keeps the whitespace that followed the word, so the words of a line join back into the line.
public struct LyricWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double
    public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
}

/// Word timing for lyrics that only carry line times. Estimated, never measured: the same line always
/// gives the same words. Technique: weight each word by its syllables, one unit per CJK character.
public enum LyricWordTiming {
    /// Seconds a unit takes to sing.
    public static let secondsPerUnit = 0.45
    /// A line is never sung faster than this, however short.
    public static let minimumSpan = 1.0

    /// How long a word takes to sing, in units. Vowel groups for Latin and Cyrillic script, one per CJK character,
    /// at least one for any word with a letter or digit, none for punctuation alone.
    public static func units(_ word: String) -> Int {
        var cjk = 0
        var other = ""
        for scalar in word.unicodeScalars {
            if isCJK(scalar) { cjk += 1 } else { other.unicodeScalars.append(scalar) }
        }
        return cjk + otherUnits(other)
    }

    /// The words of `line`, timed over a sung span of `min(lineEnd - line.time, max(1.0, units * 0.45))`.
    /// A long gap before the next line leaves the words finished early. An empty line has no words.
    /// Punctuation alone joins the word before it (or the one after it) and takes no time of its own.
    public static func words(in line: LyricLine, lineEnd: Double) -> [LyricWord] {
        let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var pieces: [(text: String, units: Int)] = []
        var prefix = ""
        for token in tokens(trimmed) {
            let count = units(token)
            if count > 0 {
                pieces.append((prefix + token, count))
                prefix = ""
            } else if pieces.isEmpty {
                prefix += token
            } else {
                pieces[pieces.count - 1].text += token
            }
        }
        if pieces.isEmpty { pieces = [(prefix, 1)] }   // nothing but punctuation: one word

        let total = Double(pieces.reduce(0) { $0 + $1.units })
        let span = max(0, min(lineEnd - line.time, max(minimumSpan, total * secondsPerUnit)))
        var boundaries = [line.time]
        var sung = 0
        for piece in pieces {
            sung += piece.units
            boundaries.append(line.time + span * Double(sung) / total)
        }
        boundaries[boundaries.count - 1] = line.time + span
        return pieces.enumerated().map { LyricWord(text: $1.text, start: boundaries[$0], end: boundaries[$0 + 1]) }
    }

    /// The word being sung at `time`: nil before the first word, the last word once the span is over.
    public static func index(_ words: [LyricWord], at time: Double) -> Int? {
        guard let first = words.first, time >= first.start else { return nil }
        var found = 0
        for (i, word) in words.enumerated() {
            if word.start <= time { found = i } else { break }
        }
        return found
    }

    /// The next time after `time` that the lit word changes, or nil when no change is left.
    public static func nextChange(_ words: [LyricWord], after time: Double) -> Double? {
        words.first { $0.start > time }?.start
    }

    // MARK: Splitting

    /// Whitespace-separated words, each CJK character alone. Whitespace stays on the token before it.
    private static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var afterSpace = false
        for character in text {
            if character.isWhitespace {
                if !current.isEmpty { current.append(character) } else if !tokens.isEmpty { tokens[tokens.count - 1].append(character) }
                afterSpace = true
                continue
            }
            if character.unicodeScalars.first.map(isCJK) == true {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(character))
            } else {
                if afterSpace, !current.isEmpty { tokens.append(current); current = "" }
                current.append(character)
            }
            afterSpace = false
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: Counting

    private static let vowels: Set<Unicode.Scalar> = Set("aeiouy\u{430}\u{435}\u{438}\u{43E}\u{443}\u{44B}\u{44D}\u{44E}\u{44F}".unicodeScalars)

    /// Vowel groups of text that is not CJK, accents ignored; one for a word that has letters but no vowel.
    private static func otherUnits(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var groups = 0
        var inGroup = false
        for scalar in folded.unicodeScalars {
            let isVowel = vowels.contains(scalar)
            if isVowel && !inGroup { groups += 1 }
            inGroup = isVowel
        }
        if groups > 0 { return groups }
        return text.unicodeScalars.contains { $0.properties.isAlphabetic || $0.properties.numericType != nil } ? 1 : 0
    }

    /// Kana, kanji and hangul syllables: scripts that are written without spaces or one syllable per character.
    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF,    // hiragana, katakana
             0x31F0...0x31FF,    // katakana extensions
             0x3400...0x4DBF,    // ideographs, extension A
             0x4E00...0x9FFF,    // ideographs
             0xF900...0xFAFF,    // compatibility ideographs
             0xFF66...0xFF9F,    // halfwidth katakana
             0xAC00...0xD7AF,    // hangul syllables
             0x20000...0x2A6DF:  // ideographs, extension B
            return true
        default:
            return false
        }
    }
}

public extension Array where Element == LyricLine {
    /// When line `index` stops being the current line: the next line's time, or `trackEnd` (at least four seconds
    /// after its start) for the last one. The same end `lineProgress` uses.
    func lineEnd(at index: Int, trackEnd: Double = 0) -> Double {
        index + 1 < count ? self[index + 1].time : Swift.max(trackEnd, self[index].time + 4)
    }
}
