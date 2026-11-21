import Foundation

enum SpokenMarkdown {
    static func apply(_ draft: SpokenDraft, language: SpokenLanguage) -> SpokenDraft {
        var text = draft.text.replacingOccurrences(of: "\r\n", with: "\n")
        text = strippingPresentation(text)
        text = unshouting(text)
        text = replacingFences(text, language: language)
        text = replacingInlineCode(text)
        text = replacingStrikethrough(text)
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

    /// Two or more fully capitalized words are shouted. The voice says them in sentence case.
    /// A one-word acknowledgement such as "OK" stays.
    private static func unshouting(_ text: String) -> String {
        SpokenText.rewrite(text, pattern: #"\b[A-Z][A-Z']*(?:\s+[A-Z][A-Z']*)+\b"#) { match, source in
            let shouted = SpokenText.group(match, 0, in: source)
            return SpokenText.capitalizingFirst(shouted.lowercased())
        }
    }

    /// Emoji and skin-tone modifiers are pictures, not words. Digits, letters, and currency
    /// signs stay, because those are spoken later.
    private static func strippingPresentation(_ text: String) -> String {
        var scalars: [Unicode.Scalar] = []
        for scalar in text.unicodeScalars {
            if scalar.value == 0x200D || scalar.value == 0xFE0E || scalar.value == 0xFE0F { continue }
            if (0x1F3FB...0x1F3FF).contains(scalar.value) { continue }
            if scalar.properties.isEmojiPresentation { continue }
            if scalar.properties.isEmoji && scalar.properties.generalCategory == .otherSymbol { continue }
            scalars.append(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func codeSummary(_ language: SpokenLanguage) -> String {
        switch language {
        case .english: "Here's the code."
        case .french: "Voici le code."
        }
    }

    private static func replacingFences(_ text: String, language: SpokenLanguage) -> String {
        let summary = "\n\(codeSummary(language))\n"
        var text = text
        let patterns = [
            #"```[^\n]*\n[\s\S]*?```"#,
            #"~{3,}[^\n]*\n[\s\S]*?~{3,}"#,
            #"```[^\n]*\n[\s\S]*$"#,
            #"~{3,}[^\n]*\n[\s\S]*$"#,
        ]
        for pattern in patterns {
            text = SpokenText.rewrite(text, pattern: pattern) { _, _ in summary }
        }
        return text
    }

    /// Struck words are retracted. The voice does not read the tildes or the deleted text.
    private static func replacingStrikethrough(_ text: String) -> String {
        SpokenText.rewrite(text, pattern: #"~~[^~\n]*~~"#) { _, _ in "" }
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
        return text.replacingOccurrences(of: " & ", with: word)
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
        guard let groups = SpokenText.prefixMatch(#"^\[([ xX])\]\s+(.+)$"#, in: body), groups.count > 2 else { return nil }
        let done = groups[1].lowercased() == "x"
        let item = groups[2]
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
