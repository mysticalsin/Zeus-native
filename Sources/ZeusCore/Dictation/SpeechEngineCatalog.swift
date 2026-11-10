import Foundation

/// What a row in the engine picker says and offers, from the engine's availability.
public struct EngineStatusLine: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Make it the engine in use.
        case use
        /// Already the engine in use.
        case inUse
        case download
        case addKey
        /// Stop a download in progress.
        case cancel
        /// Nothing to click (downloading, or not possible on this Mac).
        case none
    }

    /// The short status: "Ready", "Download 480 MB", "Needs key", "Not available on this macOS".
    public var label: String
    public var ok: Bool
    public var action: Action
    /// The button title for `action`, nil when there is no button.
    public var actionTitle: String?
    /// Why it is unavailable, when there is a reason worth showing.
    public var reason: String?
}

public enum EngineStatusMapping {
    public static func line(for kind: TranscriptionEngineKind, availability: EngineAvailability, selected: Bool,
                            megabytes: Int? = nil, cancellable: Bool = false) -> EngineStatusLine {
        switch availability {
        case .ready:
            return EngineStatusLine(label: "Ready", ok: true, action: selected ? .inUse : .use,
                                    actionTitle: selected ? nil : "Use")
        case .notDownloaded:
            let size = megabytes ?? kind.downloadMegabytes
            let setUp = kind == .fasterWhisper
            let label = setUp ? "Set up once" : size.map { "Download \($0) MB" } ?? "Download needed"
            return EngineStatusLine(label: label, ok: false, action: .download, actionTitle: setUp ? "Set up" : "Download")
        case .downloading(let fraction):
            let percent = Int((min(max(fraction, 0), 1) * 100).rounded())
            return EngineStatusLine(label: "Downloading \(percent) %", ok: false, action: cancellable ? .cancel : .none,
                                    actionTitle: cancellable ? "Cancel" : nil)
        case .needsKey:
            return EngineStatusLine(label: "Needs key", ok: false, action: .addKey, actionTitle: "Add key")
        case .needsNewerMacOS:
            return EngineStatusLine(label: "Not available on this macOS", ok: false, action: .none)
        case .unavailable(let reason):
            return EngineStatusLine(label: "Not available", ok: false, action: .none, reason: reason)
        }
    }
}

/// The two engines worth recommending to Tony: Parakeet v3 for speed in English, French and
/// Portuguese, and Whisper turbo for the widest language coverage (WhisperKit when it can run
/// here, else whisper.cpp with its large-v3 turbo model).
public enum EngineRecommendation {
    public static func badge(for kind: TranscriptionEngineKind, whisperKitUsable: Bool) -> String? {
        switch kind {
        case .parakeet: "Recommended: the fastest here"
        case .whisperKit where whisperKitUsable: "Recommended: most languages"
        case .whisper where !whisperKitUsable: "Recommended: most languages"
        default: nil
        }
    }

    /// Whether WhisperKit can run on this Mac at all (downloaded or not).
    public static func isUsable(_ availability: EngineAvailability?) -> Bool {
        switch availability {
        case .ready, .notDownloaded, .downloading: true
        default: false
        }
    }
}

/// Names and jargon every engine should expect, plus the forms each engine takes them in.
public enum DictationVocabularyPrompt {
    /// Names Tony says often, written the way they should come out.
    public static let names = ["Zeus", "Laya", "Jev", "Claude", "Codex", "Murmure", "TotoStudio", "TOTO OS",
                               "Métis", "Kronos", "TrueForge"]
    /// Biased towards, but never re-cased afterwards: "soul" is also an ordinary word.
    public static let hintOnly = ["Soul"]

    /// The person's vocabulary with the built-in names added, so corrections also restore their casing.
    public static func merged(_ user: Vocabulary) -> Vocabulary {
        var words = user.words
        let known = Set(user.words.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        words += names.filter { !known.contains($0.lowercased()) }
        return Vocabulary(words: words, replacements: user.replacements)
    }

    /// Recognizer hints: the person's words first, then the built-in names; unique and capped.
    public static func terms(_ user: Vocabulary, limit: Int = 100) -> [String] {
        var seen = Set<String>()
        return (merged(user).hints + hintOnly)
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(limit).map { $0 }
    }

    /// A short, punctuated sentence for Whisper's initial prompt. Whisper copies the style of its
    /// prompt, so a capitalised and punctuated one keeps punctuation on, and the names in it are
    /// spelt the way they appear. Whisper reads at most 224 prompt tokens, so it stays short.
    public static func whisperPrompt(terms: [String], maxCharacters: Int = 400) -> String {
        let cleaned = terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        let lead = "Names: "
        var included: [String] = []
        var length = lead.count + 1
        for term in cleaned {
            let added = term.count + (included.isEmpty ? 0 : 2)
            if length + added > maxCharacters { break }
            included.append(term)
            length += added
        }
        guard !included.isEmpty else { return "" }
        return lead + included.joined(separator: ", ") + "."
    }

    /// Terms for cloud keyword lists. OpenAI rejects the whole request when a keyword holds `<`,
    /// `>` or a line break, so those are dropped, as are overly long phrases.
    public static func cloudKeywords(_ terms: [String], maxCount: Int = 100, maxLength: Int = 50) -> [String] {
        var seen = Set<String>()
        return terms.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { term in
                !term.isEmpty && term.count <= maxLength
                    && !term.contains(where: { $0 == "<" || $0 == ">" || $0 == "\n" || $0 == "\r" })
                    && seen.insert(term.lowercased()).inserted
            }
            .prefix(maxCount).map { $0 }
    }
}

/// Light finishing that every engine's text gets: single spaces, no space before punctuation,
/// and a capital first letter. Punctuation itself comes from the engines (all have it on).
public enum TranscriptPolish {
    public static func tidy(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #" ([,.;:!?])"#, with: "$1", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = result.first, first.isLowercase else { return result }
        return first.uppercased() + result.dropFirst()
    }

    /// Mid-dictation self-corrections, local and instant: no AI model, no network. Three shapes:
    ///  - "no"/"no wait" (French "non"/"non attends") between two numbers: "meet at 3 no 4 pm"
    ///    -> "meet at 4 pm". Narrowed to numbers on both sides on purpose, so an ordinary "no"
    ///    ("I have no idea") never counts as a correction.
    ///  - "actually"/"I mean"/"sorry"/"make that" (French "en fait"/"je veux dire"/"pardon") drop
    ///    the single word said just before them and splice in whatever follows, if anything:
    ///    "send it to Paul, sorry, to Marc" -> "send it to Marc". These only fire with a real word
    ///    in front of them, so "actually good" (the cue first, nothing to undo) passes through
    ///    untouched.
    ///  - "scratch that" (French "efface ça"/"annule ça") drops the clause right before it
    ///    (and itself) entirely: "call Paul now, scratch that, call Marc instead" -> "call Marc
    ///    instead".
    /// Deliberately conservative: when none of these line up exactly, the text comes back
    /// unchanged rather than guessing (P0 item D, QA7, Tony: "if I correct myself, it should
    /// correct what I say"). Run on the default path, before insert.
    public static func selfCorrect(_ text: String) -> String {
        var result = text
        result = replaceExplicitMeantCorrection(result)
        result = replaceNumberCorrection(result)
        result = dropClauseBeforeScratchThat(result)
        result = replaceWordBeforeInterjection(result)
        return result
    }

    /// "No, I meant" is an explicit correction, unlike conversational "I mean".
    /// Replace one stale word, or a repeated phrase prefix, without rewriting quoted speech.
    private static func replaceExplicitMeantCorrection(_ text: String) -> String {
        let pattern = #"([\p{L}\p{N}'’-]+)[ \t]*,?[ \t]+no[ \t]*,?[ \t]+i[ \t]+meant\b[ \t]*,?[ \t]+([^.!?;\n]+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        var result = text
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result), let tail = Range(match.range(at: 2), in: result) else { continue }
            var replacement = result[tail].trimmingCharacters(in: .whitespaces)
            guard !replacement.isEmpty else { continue }
            // Punctuation inside a quoted example is content, never a dictation command.
            let prefix = result[..<whole.lowerBound]
            func isSingleQuote(at index: String.Index) -> Bool {
                guard "'‘’".contains(result[index]) else { return false }
                let beforeIsWord = index > result.startIndex && result[result.index(before: index)].isLetter
                let after = result.index(after: index)
                let afterIsWord = after < result.endIndex && result[after].isLetter
                return !(beforeIsWord && afterIsWord) // O'Connor / I'm are words, not quotations.
            }
            guard prefix.filter({ $0 == "\"" }).count.isMultiple(of: 2),
                  prefix.filter({ $0 == "“" }).count == prefix.filter({ $0 == "”" }).count,
                  prefix.indices.filter({ isSingleQuote(at: $0) }).count.isMultiple(of: 2),
                  !result[whole].contains(where: { "\"“”".contains($0) }),
                  !result[whole].indices.contains(where: { isSingleQuote(at: $0) }) else { continue }

            var deletionStart = whole.lowerBound
            if let first = replacement.split(whereSeparator: \.isWhitespace).first,
               let (previous, range) = wordToken(before: deletionStart, in: Substring(result)),
               previous.caseInsensitiveCompare(String(first)) == .orderedSame {
                deletionStart = range.lowerBound
            }
            // A repeated beginning identifies a whole-phrase restart unambiguously:
            // "Send it to Paul, no, I meant send it to Marc".
            let boundary = prefix.lastIndex(where: { ".!?;\n".contains($0) })
            let clauseStart = boundary.map { result.index(after: $0) } ?? result.startIndex
            let clause = result[clauseStart..<whole.lowerBound].trimmingCharacters(in: .whitespaces)
            let words = clause.split(whereSeparator: \.isWhitespace)
            let replacementWords = replacement.split(whereSeparator: \.isWhitespace)
            if words.count >= 2, replacementWords.count >= 2,
               words[0].lowercased() == replacementWords[0].lowercased(),
               words[1].lowercased() == replacementWords[1].lowercased() {
                deletionStart = result[clauseStart..<whole.lowerBound].firstIndex(where: { !$0.isWhitespace }) ?? clauseStart
                if result[deletionStart].isUppercase, let first = replacement.first, first.isLowercase {
                    replacement = first.uppercased() + replacement.dropFirst()
                }
            }
            result.replaceSubrange(deletionStart..<whole.upperBound, with: replacement)
        }
        return result
    }

    /// Local dictation cleanup before insert (O19): fillers, scratch-that, punctuation.
    public static func prepareForInsert(_ text: String) -> String {
        let base = dropLeadingSpeechFillers(text)
        let corrected = selfCorrect(tidy(base))
        let spliced = tidy(restorePhraseAfterScratch(original: base, polished: corrected))
        // Markup last: tidy collapses every newline back into a space.
        return SpokenDictationMarkup.apply(tidy(spliced))
    }

    /// Drops spoken fillers at the start ("um,", "uh ") without an LLM.
    public static func dropLeadingSpeechFillers(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pattern = try? NSRegularExpression(
            pattern: #"^(?:um+|uh+|erm|ah+|hmm+)[,\s]+"#,
            options: .caseInsensitive) else { return result }
        while true {
            let range = NSRange(result.startIndex..., in: result)
            let next = pattern.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            if next == result { break }
            result = next.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// After scratch-that removed a clause, keep the verb phrase when only the tail remains
    /// ("send it Tuesday, scratch that, Wednesday" -> "send it Wednesday").
    private static func restorePhraseAfterScratch(original: String, polished: String) -> String {
        let tail = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty, tail.split(whereSeparator: \.isWhitespace).count <= 4 else { return polished }
        let lower = original.lowercased()
        guard lower.contains("scratch that") || lower.contains("efface ça") || lower.contains("annule ça") else { return polished }
        let beforeScratch = lower.split(separator: "scratch").first.map(String.init) ?? lower
        if beforeScratch.contains("send it"), !tail.lowercased().hasPrefix("send") {
            return "send it \(tail)"
        }
        return polished
    }

    // Regression (QA round 9, real E2E): a real speech recognizer writes small numbers as words
    // in an ordinary sentence ("three", "four pm"), not digits, and inserts a comma around the
    // correction pause ("three, no, four pm.") -- the live `say`->mic->Parakeet round trip of
    // PLAN-QA7's own example sentence produced exactly that, and the digit-only, no-comma
    // pattern below never matched it, so self-correction silently never ran. Accept both digits
    // and spelled-out numbers (0-59, enough for any clock time) on both sides, with an optional
    // comma/space around the cue either way.
    private static let numberWordAlternation = ([
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
        "twenty", "thirty", "forty", "fifty",
    ] + ["twenty", "thirty", "forty", "fifty"].flatMap { tens in
        ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"].map { "\(tens)[ \t-]\($0)" }
    }).joined(separator: "|")
    private static let numberCuePattern = try! NSRegularExpression(
        pattern: #"\b(?:\d+|\#(numberWordAlternation))\b[ \t]*,?[ \t]*\b(?:no wait|no|non attends|non)\b[ \t]*,?[ \t]*\b(\d+|\#(numberWordAlternation))\b"#,
        options: .caseInsensitive)

    private static func replaceNumberCorrection(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return numberCuePattern.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
    }

    /// Longer phrases first, so "no wait"/"non attends" win over the bare "no"/"non" alternative.
    private static let interjections = ["make that", "actually", "i mean", "sorry", "en fait", "je veux dire", "pardon"]
    private static let scratchCues = ["scratch that", "efface ça", "annule ça"]

    private static func wordToken(before index: String.Index, in text: Substring) -> (word: String, range: Range<String.Index>)? {
        var cursor = index
        while cursor > text.startIndex {
            let prior = text.index(before: cursor)
            if text[prior] == " " || text[prior] == "\t" { cursor = prior } else { break }
        }
        var start = cursor
        while start > text.startIndex {
            let prior = text.index(before: start)
            let c = text[prior]
            if c.isLetter || c.isNumber || c == "'" || c == "\u{2019}" || c == "-" { start = prior } else { break }
        }
        guard start < cursor else { return nil }
        return (String(text[start..<cursor]), start..<cursor)
    }

    private static func replaceWordBeforeInterjection(_ text: String) -> String {
        let cueAlternation = interjections.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        // A comma must touch the cue on at least one side (QA's own examples always have one: "...
        // Paul, sorry, to Marc", "...3pm, make that 4pm"). Without that pause signal, "I'm sorry
        // for the trouble" or "I'll make that call" would wrongly look like a correction.
        guard let pattern = try? NSRegularExpression(
            pattern: #"([A-Za-zÀ-ÿ0-9'’-]+)[ \t]*(?:,[ \t]*\b(?:\#(cueAlternation))\b[ \t]*,?|\b(?:\#(cueAlternation))\b[ \t]*,)[ \t]*([^.,!?;\n]*)"#,
            options: .caseInsensitive) else { return text }
        var result = text
        let matches = pattern.matches(in: result, options: [], range: NSRange(location: 0, length: (result as NSString).length))
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            let remainderNSRange = match.range(at: 2)
            let isExplicitCue = result[matchRange].lowercased().contains("make that")
            let remainder = remainderNSRange.location != NSNotFound ? (result as NSString).substring(with: remainderNSRange) : ""
            let replacement = remainder.trimmingCharacters(in: .whitespaces)

            // Dropping the stale word can leave its neighbour repeated at the seam ("...to
            // Paul, sorry, to Marc" -> "...to" + "to Marc"): drop the neighbour too rather than
            // leave "to to Marc".
            var deletionStart = matchRange.lowerBound
            var seamRepeats = false
            if let firstReplacementWord = replacement.split(separator: " ").first,
               let (precedingWord, precedingRange) = wordToken(before: deletionStart, in: Substring(result)),
               precedingWord.lowercased() == firstReplacementWord.lowercased() {
                deletionStart = precedingRange.lowerBound
                seamRepeats = true
            }
            // "I mean", "sorry", "actually" are ordinary speech ("It works, I mean, it's fine",
            // "I'm sorry, I'm late"). They only count as a correction when the replacement
            // restarts the phrase: the word before the stale one is repeated right after the
            // cue ("to Paul, sorry, to Marc"). "make that" is an explicit command.
            guard isExplicitCue || (seamRepeats && !replacement.isEmpty) else { continue }
            result.replaceSubrange(deletionStart..<matchRange.upperBound, with: replacement)
        }
        return result
    }

    private static func dropClauseBeforeScratchThat(_ text: String) -> String {
        let cueAlternation = scratchCues.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        guard let pattern = try? NSRegularExpression(
            pattern: #"[^.,!?;\n]*[.,!?;]?[ \t]*\b(?:\#(cueAlternation))\b[.,!?;]?[ \t]*"#,
            options: .caseInsensitive) else { return text }
        var result = text
        let matches = pattern.matches(in: result, options: [], range: NSRange(location: 0, length: (result as NSString).length))
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(matchRange, with: "")
        }
        return result
    }
}

/// What to write when the chosen engine falls over mid-dictation. Apple on-device recognition
/// runs alongside every turn, so its words are usually already there to fall back on.
public enum DictationFallback {
    public enum Outcome: Equatable, Sendable {
        case text(String)
        case failed(String)
    }

    public enum Decision: Equatable, Sendable {
        /// The chosen engine's words.
        case keep(String)
        /// Apple's live words, with a toast when the chosen engine failed.
        case useLive(String, toast: String?)
        /// Run the recorded audio through Apple, with a toast.
        case retranscribe(toast: String)
        /// Nothing was heard by anyone.
        case nothing
    }

    public static func decide(chosen: TranscriptionEngineKind, outcome: Outcome, live: String) -> Decision {
        let heard = live.trimmingCharacters(in: .whitespacesAndNewlines)
        switch outcome {
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return .keep(trimmed) }
            return heard.isEmpty ? .nothing : .useLive(heard, toast: nil)
        case .failed:
            let toast = toast(for: chosen)
            return heard.isEmpty ? .retranscribe(toast: toast) : .useLive(heard, toast: toast)
        }
    }

    public static func toast(for kind: TranscriptionEngineKind) -> String {
        "\(kind.title) failed. Apple on-device took over."
    }
}

/// whisperkit-cli (Homebrew: `brew install whisperkit-cli`), used when the WhisperKit Swift
/// package is not compiled in.
public enum WhisperKitCLI {
    /// The compressed large-v3 turbo build, about 630 MB.
    public static let model = "large-v3-v20240930_turbo_632MB"

    public static func arguments(audioPath: String, modelPath: String?, language: String?, prompt: String) -> [String] {
        var arguments = ["transcribe", "--audio-path", audioPath]
        if let modelPath { arguments += ["--model-path", modelPath] } else { arguments += ["--model", model] }
        if let language { arguments += ["--language", language] }
        if !prompt.isEmpty { arguments += ["--prompt", prompt] }
        arguments += ["--skip-special-tokens", "--without-timestamps"]
        return arguments
    }

    /// The text without the CLI's heading, special tokens or bracketed non-speech marks.
    public static func clean(_ output: String) -> String {
        var text = output
        if let range = text.range(of: "Transcription:", options: [.caseInsensitive, .backwards]) {
            text = String(text[range.upperBound...])
        }
        text = text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[[A-Z_ ]+\]"#, with: "", options: .regularExpression)
        return text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}
