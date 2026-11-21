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
            return spokenLink(pieces.core, language: language) + pieces.punctuation
        }
    }

    private static func replacingWindowsPaths(_ text: String, language: SpokenLanguage) -> String {
        SpokenText.rewrite(text, pattern: #"[A-Za-z]:\\[^\s]+"#) { match, source in
            spokenFile(SpokenText.group(match, 0, in: source), language: language)
        }
    }

    /// A slash path with a file extension. `and/or` and `12/11/2026` have no extension, so they stay.
    private static func replacingUnixPaths(_ text: String, language: SpokenLanguage) -> String {
        let pattern = #"(?<![A-Za-z0-9_])(?:\.\./|\./|/)?[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)+\.[A-Za-z0-9]{1,12}\b"#
        return SpokenText.rewrite(text, pattern: pattern) { match, source in
            spokenFile(SpokenText.group(match, 0, in: source), language: language)
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

    /// Host and path are spoken. The query string stays out.
    private static func spokenLink(_ url: String, language: SpokenLanguage) -> String {
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
        let joiner: String
        let slash: String
        switch language {
        case .english:
            joiner = " dot "
            slash = " slash "
        case .french:
            joiner = " point "
            slash = " barre oblique "
        }
        let hostWords: String
        if labels.isEmpty || labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            switch language {
            case .english: hostWords = "a link"
            case .french: hostWords = "un lien"
            }
        } else {
            hostWords = labels.joined(separator: joiner)
        }
        let pathText = String(body[hostEnd...])
        let pathEnd = pathText.firstIndex { "?#".contains($0) } ?? pathText.endIndex
        let segments = pathText[..<pathEnd].split(separator: "/").map(String.init).filter { !$0.isEmpty }
        if segments.isEmpty { return hostWords }
        return hostWords + slash + segments.joined(separator: slash)
    }

    /// The directories stay quiet. The file name is what a screen reader needs.
    private static func spokenFile(_ path: String, language: SpokenLanguage) -> String {
        let pieces = peelingPunctuation(path)
        let name = pieces.core.split { $0 == "/" || $0 == "\\" }.last.map(String.init) ?? pieces.core
        let noun: String
        let dotWord: String
        switch language {
        case .english:
            noun = "file"
            dotWord = "dot"
        case .french:
            noun = "fichier"
            dotWord = "point"
        }
        let spoken: String
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            let base = String(name[..<dot])
            let ext = String(name[name.index(after: dot)...])
            spoken = ext.isEmpty ? "\(noun) \(base)" : "\(noun) \(base) \(dotWord) \(ext)"
        } else {
            spoken = "\(noun) \(name)"
        }
        return spoken + pieces.punctuation
    }

    private static func hashWord(_ language: SpokenLanguage) -> String {
        switch language {
        case .english: "a hash"
        case .french: "une empreinte"
        }
    }
}
