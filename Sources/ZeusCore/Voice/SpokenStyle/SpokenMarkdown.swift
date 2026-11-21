import Foundation

enum SpokenMarkdown {
    static func apply(_ draft: SpokenDraft, language: SpokenLanguage) -> SpokenDraft {
        var text = draft.text.replacingOccurrences(of: "\r\n", with: "\n")
        text = strippingPresentation(text)
        text = replacingFences(text, language: language)
        text = replacingInlineCode(text)
        text = replacingImages(text, language: language)
        text = replacingLinks(text)
        text = replacingEmphasis(text)
        text = replacingHeadersAndLists(text, language: language)
        return SpokenDraft(text: SpokenText.collapse(text), runs: [])
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
        let closed = SpokenText.rewrite(text, pattern: #"```[^\n]*\n[\s\S]*?```"#) { _, _ in summary }
        return SpokenText.rewrite(closed, pattern: #"```[^\n]*\n[\s\S]*$"#) { _, _ in summary }
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
        while index < lines.count {
            if let item = listItem(lines[index]) {
                var items = [item]
                index += 1
                while index < lines.count, let next = listItem(lines[index]) {
                    items.append(next)
                    index += 1
                }
                output.append(sequence(items, language: language))
                continue
            }
            output.append(plainLine(lines[index]))
            index += 1
        }
        return output.joined(separator: "\n")
    }

    private static func listItem(_ line: String) -> String? {
        guard let groups = SpokenText.prefixMatch(#"^\s*(?:[-*+]|\d+[.)])\s+(.+)$"#, in: line) else { return nil }
        return groups.count > 1 ? groups[1] : nil
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
