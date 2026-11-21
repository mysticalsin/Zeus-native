import Foundation

enum SpokenLinks {
    static func apply(_ draft: SpokenDraft, language: SpokenLanguage) -> SpokenDraft {
        var text = draft.text
        text = replacingURLs(text, language: language)
        text = replacingWindowsPaths(text, language: language)
        text = replacingUnixPaths(text, language: language)
        text = replacingHashes(text, language: language)
        return SpokenDraft(text: SpokenText.collapse(text), runs: [])
    }

    private static func replacingURLs(_ text: String, language: SpokenLanguage) -> String {
        SpokenText.rewrite(text, pattern: #"(?i)\b(?:https?://|www\.)[^\s<>\[\]()]+"#) { match, source in
            let raw = SpokenText.group(match, 0, in: source)
            let pieces = peelingPunctuation(raw)
            return domain(of: pieces.core, language: language) + pieces.punctuation
        }
    }

    private static func replacingWindowsPaths(_ text: String, language: SpokenLanguage) -> String {
        SpokenText.rewrite(text, pattern: #"[A-Za-z]:\\[^\s]+"#) { match, source in
            let raw = SpokenText.group(match, 0, in: source)
            let pieces = peelingPunctuation(raw)
            return fileWord(language) + pieces.punctuation
        }
    }

    /// A slash path with a file extension. `and/or` and `12/11/2026` have no extension, so they stay.
    private static func replacingUnixPaths(_ text: String, language: SpokenLanguage) -> String {
        let pattern = #"(?<![A-Za-z0-9_])(?:\.\./|\./|/)?[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)+\.[A-Za-z0-9]{1,12}\b"#
        return SpokenText.rewrite(text, pattern: pattern) { _, _ in
            fileWord(language)
        }
    }

    private static func replacingHashes(_ text: String, language: SpokenLanguage) -> String {
        let pattern = #"\b(?:0x[0-9a-fA-F]{6,64}|[0-9a-fA-F]{7,64})\b"#
        return SpokenText.rewrite(text, pattern: pattern) { match, source in
            let token = SpokenText.group(match, 0, in: source)
            guard isHash(token) else { return token }
            return hashWord(language)
        }
    }

    /// A run of digits is a number, not a hash. A hash has a hex letter, a `0x` prefix, or the
    /// length of a digest.
    private static func isHash(_ token: String) -> Bool {
        let body = token.lowercased().hasPrefix("0x") ? String(token.dropFirst(2)) : token
        guard body.count >= 7, body.allSatisfy(\.isHexDigit) else { return false }
        if token.lowercased().hasPrefix("0x") || body.count >= 32 { return true }
        return body.contains { character in
            guard let scalar = character.unicodeScalars.first else { return false }
            return (scalar.value >= 97 && scalar.value <= 102) || (scalar.value >= 65 && scalar.value <= 70)
        }
    }

    private static func peelingPunctuation(_ raw: String) -> (core: String, punctuation: String) {
        var core = raw
        var punctuation = ""
        while let last = core.last, ".,;:!?".contains(last) {
            punctuation.insert(last, at: punctuation.startIndex)
            core.removeLast()
        }
        return (core, punctuation)
    }

    private static func domain(of url: String, language: SpokenLanguage) -> String {
        var body = url
        let lower = body.lowercased()
        if lower.hasPrefix("https://") {
            body.removeFirst(8)
        } else if lower.hasPrefix("http://") {
            body.removeFirst(7)
        }
        if body.lowercased().hasPrefix("www.") { body.removeFirst(4) }
        let hostEnd = body.firstIndex { "/?#".contains($0) } ?? body.endIndex
        var host = String(body[..<hostEnd])
        if let colon = host.lastIndex(of: ":"), host[host.index(after: colon)...].allSatisfy(\.isNumber) {
            host = String(host[..<colon])
        }
        let labels = host.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        if labels.isEmpty || labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            switch language {
            case .english: return "a link"
            case .french: return "un lien"
            }
        }
        let joiner: String
        switch language {
        case .english: joiner = " dot "
        case .french: joiner = " point "
        }
        return labels.joined(separator: joiner)
    }

    private static func fileWord(_ language: SpokenLanguage) -> String {
        switch language {
        case .english: "a file"
        case .french: "un fichier"
        }
    }

    private static func hashWord(_ language: SpokenLanguage) -> String {
        switch language {
        case .english: "a hash"
        case .french: "une empreinte"
        }
    }
}
