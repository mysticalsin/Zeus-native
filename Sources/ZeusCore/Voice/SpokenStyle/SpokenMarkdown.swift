import Foundation

enum SpokenMarkdown {
    static func apply(_ draft: SpokenDraft, language: SpokenLanguage) -> SpokenDraft {
        var text = draft.text.replacingOccurrences(of: "\r\n", with: "\n")
        text = replacingSymbols(text, language: language)
        text = strippingComments(text)
        text = unshouting(text)
        text = replacingFences(text, language: language)
        text = replacingInlineCode(text)
        text = replacingStrikethrough(text, language: language)
        text = replacingImages(text, language: language)
        text = replacingLinks(text)
        text = replacingAutolinks(text)
        text = replacingBreakTags(text)
        text = replacingTags(text)
        text = replacingAmpersands(text, language: language)
        text = replacingParentheses(text)
        text = replacingEmphasis(text)
        text = replacingHeadersAndLists(text, language: language)
        return SpokenDraft(text: SpokenText.collapse(text), runs: [])
    }

    /// Shouted prose becomes sentence case. Short all-caps tokens such as NASA and API stay.
    private static let functionWords: Set<String> = [
        "I", "A", "AN", "AM", "THE", "AND", "OR", "BUT", "FOR", "NOT", "TO", "OF",
        "IN", "ON", "AT", "BY", "IS", "IT", "BE", "WE", "HE", "MY", "DO", "SO",
        "NO", "UP", "IF", "AS", "ARE", "WAS", "HAS", "HAD",
    ]

    private static func unshouting(_ text: String) -> String {
        var tokens: [(word: Bool, text: String)] = []
        var current = ""
        var inWord = false
        for character in text {
            let wordCharacter = character.isLetter || character == "'"
            if wordCharacter == inWord {
                current.append(character)
            } else {
                if !current.isEmpty { tokens.append((inWord, current)) }
                current = String(character)
                inWord = wordCharacter
            }
        }
        if !current.isEmpty { tokens.append((inWord, current)) }
        var result = ""
        var index = 0
        while index < tokens.count {
            if !tokens[index].word {
                result += tokens[index].text
                index += 1
                continue
            }
            var run = [index]
            var cursor = index
            while cursor + 2 < tokens.count,
                  tokens[cursor + 1].text == " ",
                  tokens[cursor + 2].word,
                  isAllCaps(tokens[cursor + 2].text),
                  isAllCaps(tokens[cursor].text) {
                run.append(cursor + 2)
                cursor += 2
            }
            let shouted = isAllCaps(tokens[index].text) && run.contains { token in
                let word = tokens[token].text
                return word.count >= 5 || functionWords.contains(word.uppercased())
            }
            if shouted, run.count > 1 || (run.count == 1 && functionWords.contains(tokens[index].text.uppercased()) && tokens[index].text.count >= 5) {
                let end = run[run.count - 1]
                var piece = ""
                for token in index...end { piece += tokens[token].text }
                result += SpokenText.capitalizingFirst(piece.lowercased())
                index = end + 1
            } else {
                result += tokens[index].text
                index += 1
            }
        }
        return result
    }

    private static func isAllCaps(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        return !letters.isEmpty && letters.allSatisfy(\.isUppercase)
    }

    /// Emoji become words. Keycap digits stay digits. Bidi overrides and zero-width spaces go.
    private static func replacingSymbols(_ text: String, language: SpokenLanguage) -> String {
        let scalars = Array(text.unicodeScalars)
        var result = ""
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if isHiddenScalar(scalar) {
                index += 1
                continue
            }
            if isKeycapBase(scalar), index + 1 < scalars.count, scalars[index + 1].value == 0x20E3 {
                result.unicodeScalars.append(scalar)
                index += 2
                continue
            }
            if isKeycapBase(scalar), index + 2 < scalars.count,
               scalars[index + 1].value == 0xFE0F, scalars[index + 2].value == 0x20E3 {
                result.unicodeScalars.append(scalar)
                index += 3
                continue
            }
            if scalar.value == 0x20E3 {
                index += 1
                continue
            }
            if isEmoji(scalar) {
                if let last = result.last, !last.isWhitespace { result.append(" ") }
                result += emojiName(scalar, language: language)
                result.append(" ")
                index += 1
                continue
            }
            result.unicodeScalars.append(scalar)
            index += 1
        }
        return result
    }

    private static func isHiddenScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value == 0x200B || scalar.value == 0x200D || scalar.value == 0xFE0E || scalar.value == 0xFE0F {
            return true
        }
        if (0x202A...0x202E).contains(scalar.value) { return true }
        if (0x2066...0x2069).contains(scalar.value) { return true }
        if (0x1F3FB...0x1F3FF).contains(scalar.value) { return true }
        return false
    }

    private static func isKeycapBase(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.numericType == .decimal || scalar.value == 0x23 || scalar.value == 0x2A
    }

    private static func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isEmojiPresentation { return true }
        return scalar.properties.isEmoji && scalar.properties.generalCategory == .otherSymbol
    }

    private static func emojiName(_ scalar: Unicode.Scalar, language: SpokenLanguage) -> String {
        switch scalar.value {
        case 0x1F680:
            switch language {
            case .english: return "rocket"
            case .french: return "fusée"
            }
        case 0x1F44D:
            switch language {
            case .english: return "thumbs up"
            case .french: return "pouce levé"
            }
        default:
            switch language {
            case .english: return "an emoji"
            case .french: return "un emoji"
            }
        }
    }

    /// Closed comments disappear. An unclosed comment ends at the line, so later lines stay.
    private static func strippingComments(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix("<!--") {
                let start = text.index(index, offsetBy: 4)
                if let close = text[start...].range(of: "-->") {
                    index = close.upperBound
                    continue
                }
                if let newline = text[start...].firstIndex(of: "\n") {
                    index = newline
                    continue
                }
                break
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private static func codeSummary(_: String, language: SpokenLanguage) -> String {
        switch language {
        case .english: "Here's the code."
        case .french: "Voici le code."
        }
    }

    /// Line scan. A run of tildes is not fed to a backtracking expression.
    /// An opener with no closer stays as text, so the rest of the reply is kept.
    private static func replacingFences(_ text: String, language: SpokenLanguage) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var index = 0
        while index < lines.count {
            if let open = fenceOpen(lines[index]) {
                var closer: Int?
                var cursor = index + 1
                while cursor < lines.count {
                    if fenceClose(lines[cursor], matching: open) {
                        closer = cursor
                        break
                    }
                    cursor += 1
                }
                if let closer {
                    let body = lines[(index + 1)..<closer].joined(separator: "\n")
                    output.append(codeSummary(body, language: language))
                    index = closer + 1
                    continue
                }
            }
            output.append(lines[index])
            index += 1
        }
        return output.joined(separator: "\n")
    }

    private static func fenceOpen(_ line: String) -> (mark: Character, count: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let mark = trimmed.first, mark == "`" || mark == "~" else { return nil }
        var count = 0
        for character in trimmed {
            if character == mark { count += 1 } else { break }
        }
        guard count >= 3 else { return nil }
        let rest = trimmed.dropFirst(count)
        if rest.isEmpty { return (mark, count) }
        let tag = rest.allSatisfy { $0.isLetter || $0.isNumber || "+#.-_".contains($0) }
        return tag ? (mark, count) : nil
    }

    private static func fenceClose(_ line: String, matching open: (mark: Character, count: Int)) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= open.count, trimmed.allSatisfy({ $0 == open.mark }) else { return false }
        return true
    }

    /// Struck words stay, with a spoken mark, so a screen reader does not lose them.
    private static func replacingStrikethrough(_ text: String, language: SpokenLanguage) -> String {
        SpokenText.rewrite(text, pattern: #"~~([^~\n]*)~~"#) { match, source in
            let words = SpokenText.group(match, 1, in: source).trimmingCharacters(in: .whitespacesAndNewlines)
            if words.isEmpty { return "" }
            switch language {
            case .english: return "\(words), struck through,"
            case .french: return "\(words), barré,"
            }
        }
    }

    private static func replacingInlineCode(_ text: String) -> String {
        SpokenText.rewrite(text, pattern: #"`([^`\n]+)`"#) { match, source in
            SpokenText.group(match, 1, in: source).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func replacingImages(_ text: String, language: SpokenLanguage) -> String {
        SpokenText.rewrite(text, pattern: #"!\[([^\]]*)\]\(([^)\s]+)\)"#) { match, source in
            let alt = SpokenText.group(match, 1, in: source).trimmingCharacters(in: .whitespacesAndNewlines)
            if alt.isEmpty {
                switch language {
                case .english: return "an image"
                case .french: return "une image"
                }
            }
            return alt
        }
    }

    /// A markdown link keeps its label. A label that is itself a URL is left as the URL so the
    /// links stage can summarize the domain.
    private static func replacingLinks(_ text: String) -> String {
        SpokenText.rewrite(text, pattern: #"(?<!!)\[([^\]]*)\]\(([^)\s]+)\)"#) { match, source in
            let label = SpokenText.group(match, 1, in: source).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = SpokenText.group(match, 2, in: source)
            if label.isEmpty || looksLikeURL(label) { return url }
            return label
        }
    }

    private static func looksLikeURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("://") || lower.hasPrefix("www.")
    }

    /// `<https://example.com/docs>` is an autolink. The brackets are markup, not words.
    private static func replacingAutolinks(_ text: String) -> String {
        SpokenText.rewrite(text, pattern: #"<\s*((?:https?://|www\.)[^>\s]+)\s*>"#) { match, source in
            SpokenText.group(match, 1, in: source)
        }
    }

    /// `<br>` is a line break the voice should hear as a new sentence.
    private static func replacingBreakTags(_ text: String) -> String {
        let expression = SpokenText.regex(#"<\s*br\s*/?\s*>"#, options: [.caseInsensitive])
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if matches.isEmpty { return text }
        var result = ""
        var cursor = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[cursor..<range.lowerBound]
            result += ". "
            var next = range.upperBound
            while next < text.endIndex, text[next].isWhitespace { next = text.index(after: next) }
            if next < text.endIndex, text[next].isLowercase {
                result += String(text[next]).uppercased()
                next = text.index(after: next)
            }
            cursor = next
        }
        result += text[cursor...]
        return result
    }

    private static func replacingTags(_ text: String) -> String {
        SpokenText.rewrite(text, pattern: #"</?[A-Za-z][^>]*>"#) { _, _ in "" }
    }

    private static func replacingAmpersands(_ text: String, language: SpokenLanguage) -> String {
        let word: String
        switch language {
        case .english: word = " and "
        case .french: word = " et "
        }
        var text = text.replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "&amp;", with: word, options: .caseInsensitive)
        text = text.replacingOccurrences(of: " & ", with: word)
        return SpokenText.rewrite(text, pattern: #"(?<=[\p{L}\p{N}])&(?=[\p{L}\p{N}])"#) { _, _ in word }
    }

    /// A parenthetical aside is a clause, not the words "open parenthesis".
    private static func replacingParentheses(_ text: String) -> String {
        SpokenText.rewrite(text, pattern: #"\(([^()\n]+)\)"#) { match, source in
            let inner = SpokenText.group(match, 1, in: source).trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.isEmpty { return "" }
            return ", \(inner),"
        }
    }

    private static func replacingEmphasis(_ text: String) -> String {
        var current = text
        for _ in 0..<4 {
            let next = SpokenText.rewrite(current, pattern: #"\*\*([^*\n]+)\*\*"#) { match, source in
                SpokenText.group(match, 1, in: source)
            }
            let underscores = SpokenText.rewrite(next, pattern: #"__([^_\n]+)__"#) { match, source in
                SpokenText.group(match, 1, in: source)
            }
            let italic = SpokenText.rewrite(underscores, pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#) { match, source in
                SpokenText.group(match, 1, in: source)
            }
            let word = SpokenText.rewrite(italic, pattern: #"(?<![A-Za-z0-9])_([^_\n]+)_(?![A-Za-z0-9])"#) { match, source in
                SpokenText.group(match, 1, in: source)
            }
            if word == current { break }
            current = word
        }
        current = current.replacingOccurrences(of: "**", with: "")
        current = current.replacingOccurrences(of: "~~", with: "")
        current = current.replacingOccurrences(of: "__", with: "")
        return current
    }

    private static func replacingHeadersAndLists(_ text: String, language: SpokenLanguage) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var index = 0
        var lowerNext = false
        while index < lines.count {
            if isListLine(lines[index]) {
                var items: [String] = []
                while index < lines.count, let item = listItem(lines[index], language: language) {
                    items.append(item)
                    index += 1
                }
                lowerNext = false
                output.append(sequence(items, language: language))
                continue
            }
            if let title = headingTitle(lines[index]), proseFollows(lines, after: index) {
                output.append(title + ",")
                lowerNext = true
                index += 1
                continue
            }
            var line = plainLine(lines[index])
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                output.append(line)
                index += 1
                continue
            }
            if lowerNext {
                line = SpokenText.lowercasingFirst(line)
                lowerNext = false
            }
            output.append(line)
            index += 1
        }
        return output.joined(separator: "\n")
    }

    /// A heading with a paragraph after it is a lead-in, not the whole answer. Alone, it stays a sentence.
    private static func proseFollows(_ lines: [String], after index: Int) -> Bool {
        var cursor = index + 1
        while cursor < lines.count {
            if lines[cursor].trimmingCharacters(in: .whitespaces).isEmpty {
                cursor += 1
                continue
            }
            if isListLine(lines[cursor]) || headingTitle(lines[cursor]) != nil { return false }
            return true
        }
        return false
    }

    private static func headingTitle(_ line: String) -> String? {
        guard let groups = SpokenText.prefixMatch(#"^\s*#{1,6}\s+(.+?)\s*$"#, in: line), groups.count > 1 else { return nil }
        var title = groups[1]
        while title.last == "#" || title.last == " " { title.removeLast() }
        let text = bare(title)
        return text.isEmpty ? nil : text
    }

    private static func isListLine(_ line: String) -> Bool {
        SpokenText.prefixMatch(#"^\s*(?:[-*+]|\d+[.)])\s+(.+)$"#, in: line) != nil
    }

    private static func listItem(_ line: String, language: SpokenLanguage) -> String? {
        guard let groups = SpokenText.prefixMatch(#"^\s*(?:[-*+]|\d+[.)])\s+(.+)$"#, in: line), groups.count > 1 else {
            return nil
        }
        return spokenCheckbox(groups[1], language: language) ?? groups[1]
    }

    private static func spokenCheckbox(_ body: String, language: SpokenLanguage) -> String? {
        guard let groups = SpokenText.prefixMatch(#"^\[([ xX])\]\s*(.+)$"#, in: body), groups.count > 2 else { return nil }
        let done = groups[1].lowercased() == "x"
        var item = groups[2].trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = item.last, ".!?".contains(last) { item.removeLast() }
        item = item.trimmingCharacters(in: .whitespacesAndNewlines)
        switch language {
        case .english:
            return done ? "\(item), done" : "\(item), still open"
        case .french:
            return done ? "\(item), fait" : "\(item), encore ouvert"
        }
    }

    private static func plainLine(_ line: String) -> String {
        if SpokenText.prefixMatch(#"^\s*([-*_])\1{2,}\s*$"#, in: line) != nil { return "" }
        if let quote = SpokenText.prefixMatch(#"^\s*>\s?(.*)$"#, in: line) {
            return headingOrText(quote.count > 1 ? quote[1] : "")
        }
        return headingOrText(line)
    }

    private static func headingOrText(_ line: String) -> String {
        guard let groups = SpokenText.prefixMatch(#"^\s*#{1,6}\s+(.+?)\s*$"#, in: line), groups.count > 1 else {
            return line
        }
        var title = groups[1]
        while title.last == "#" || title.last == " " { title.removeLast() }
        return sentence(title)
    }

    private static func sequence(_ items: [String], language: SpokenLanguage) -> String {
        let bodies = items.map(bare).filter { !$0.isEmpty }
        guard !bodies.isEmpty else { return "" }
        if bodies.count == 1 { return punctuated(bodies[0]) }
        return bodies.enumerated().map { index, body in
            let lead = leadIn(index: index, count: bodies.count, language: language)
            return "\(lead), \(punctuated(body))"
        }.joined(separator: " ")
    }

    private static func leadIn(index: Int, count: Int, language: SpokenLanguage) -> String {
        let first = index == 0
        let last = index == count - 1
        switch language {
        case .english:
            if first { return "First" }
            if last { return "And last" }
            return "Next"
        case .french:
            if first { return "D'abord" }
            if last { return "Et enfin" }
            return "Ensuite"
        }
    }

    private static func bare(_ item: String) -> String {
        var text = item.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.last == "." { text.removeLast() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func punctuated(_ body: String) -> String {
        if let last = body.last, "?!".contains(last) { return body }
        return body + "."
    }

    private static func sentence(_ body: String) -> String {
        punctuated(bare(body))
    }
}
