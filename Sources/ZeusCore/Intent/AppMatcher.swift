import Foundation

/// An installed (or running) app as the fast path knows it.
public struct AppEntry: Equatable, Sendable {
    public var name: String
    public var bundleID: String
    public var path: String
    /// Extra names it answers to ("chrome", "vs code").
    public var aliases: [String]

    public init(name: String, bundleID: String, path: String = "", aliases: [String] = []) {
        self.name = name; self.bundleID = bundleID; self.path = path; self.aliases = aliases
    }
}

/// Fuzzy app-name matching with a confidence score. Exact names and aliases score 1; spacing
/// differences ("face time", "vscode") 0.97; word prefixes ("visual studio") about 0.88;
/// initials ("vsc") 0.8; small mishearings by edit distance. Two different apps scoring within
/// 0.05 of each other is ambiguous and drops the confidence, so the LLM gets those.
public struct AppMatcher: Sendable {
    public struct Match: Equatable, Sendable {
        public let entry: AppEntry
        public let score: Double
    }

    /// Below this the fast path hands the request on.
    public static let threshold = 0.74

    private struct Prepared: Sendable {
        let entry: AppEntry
        let keys: [String]        // normalised name and aliases
        let squashed: [String]    // same, without spaces
        let tokens: [String]      // words of the name
        let initials: String
    }

    private let prepared: [Prepared]

    public init(_ entries: [AppEntry]) {
        var seen = Set<String>()
        var prepared: [Prepared] = []
        for entry in entries where seen.insert(entry.bundleID.isEmpty ? entry.path : entry.bundleID).inserted {
            var keys = [Self.normalize(entry.name)] + entry.aliases.map(Self.normalize)
            keys += Self.derivedAliases(entry.name)
            keys += (Self.builtInAliases[entry.bundleID] ?? []).map(Self.normalize)
            keys = keys.filter { !$0.isEmpty }
            var unique: [String] = []
            for key in keys where !unique.contains(key) { unique.append(key) }
            let tokens = Self.normalize(entry.name).split(separator: " ").map(String.init)
            prepared.append(Prepared(entry: entry, keys: unique, squashed: unique.map { $0.replacingOccurrences(of: " ", with: "") },
                                     tokens: tokens, initials: String(tokens.compactMap(\.first))))
        }
        self.prepared = prepared
    }

    public var count: Int { prepared.count }

    /// Candidates for `query`, best first, with their raw scores (no ambiguity applied).
    public func ranked(_ query: String, limit: Int = 3) -> [Match] {
        let q = Self.normalize(query)
        guard !q.isEmpty else { return [] }
        let squashed = q.replacingOccurrences(of: " ", with: "")
        let words = q.split(separator: " ").map(String.init)
        var scored: [Match] = []
        for app in prepared {
            let s = score(app, q, squashed, words)
            if s > 0.5 { scored.append(Match(entry: app.entry, score: s)) }
        }
        scored.sort { $0.score > $1.score || ($0.score == $1.score && $0.entry.name.count < $1.entry.name.count) }
        return Array(scored.prefix(limit))
    }

    /// Two different apps within 0.05 of each other, neither an exact name or alias.
    public static func isAmbiguous(_ ranked: [Match]) -> Bool {
        guard ranked.count > 1, ranked[0].score < 1 else { return false }
        return ranked[0].score - ranked[1].score < 0.05 && ranked[0].entry.bundleID != ranked[1].entry.bundleID
    }

    /// The best app for `query` and its confidence, ambiguity already applied. nil when nothing is close.
    public func best(_ query: String) -> Match? {
        let list = ranked(query)
        guard let top = list.first else { return nil }
        return Self.isAmbiguous(list) ? Match(entry: top.entry, score: top.score - 0.2) : top
    }

    /// `best` when it clears the threshold.
    public func confident(_ query: String, threshold: Double = AppMatcher.threshold) -> Match? {
        guard let match = best(query), match.score >= threshold else { return nil }
        return match
    }

    private func score(_ app: Prepared, _ q: String, _ squashed: String, _ words: [String]) -> Double {
        if app.keys.contains(q) { return 1 }
        if app.squashed.contains(squashed) { return 0.97 }
        var best = 0.0
        // Every query word starts a name word, in order: "visual studio" → Visual Studio Code.
        if !words.isEmpty, words.count <= app.tokens.count {
            var t = 0, ok = true
            for word in words {
                while t < app.tokens.count, !app.tokens[t].hasPrefix(word) { t += 1 }
                if t == app.tokens.count { ok = false; break }
                t += 1
            }
            if ok, squashed.count >= 3 {
                let coverage = Double(words.joined().count) / Double(max(app.tokens.joined().count, 1))
                best = max(best, 0.80 + 0.12 * coverage)
            }
        }
        if squashed.count >= 3, squashed == app.initials { best = max(best, 0.8) }
        // Mishearings: same first letter, small edit distance; short names must be nearly exact.
        for key in app.squashed where key.first == squashed.first {
            let distance = Self.editDistance(squashed, key)
            let length = max(squashed.count, key.count)
            let similarity = 1 - Double(distance) / Double(length)
            let needed = length <= 6 ? 0.85 : 0.75
            if similarity >= needed { best = max(best, similarity * 0.98) }
        }
        return best
    }

    // MARK: Names

    public static func normalize(_ text: String) -> String {
        var s = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        if s.hasSuffix(".app") { s.removeLast(4) }
        let mapped = s.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    private static let vendors = ["google", "microsoft", "adobe", "apple", "jetbrains", "mozilla", "the"]

    /// "Google Chrome" → "chrome", "Adobe Photoshop 2025" → "photoshop", "Microsoft Word" → "word".
    static func derivedAliases(_ name: String) -> [String] {
        var tokens = normalize(name).split(separator: " ").map(String.init)
        var out: [String] = []
        while let last = tokens.last, tokens.count > 1, Int(last) != nil || ["beta", "preview", "insiders", "ce"].contains(last) {
            tokens.removeLast(); out.append(tokens.joined(separator: " "))
        }
        if tokens.count > 1, let first = tokens.first, vendors.contains(first) {
            out.append(tokens.dropFirst().joined(separator: " "))
        }
        return out
    }

    /// Common spoken names, keyed by bundle ID, used only when that app is installed.
    public static let builtInAliases: [String: [String]] = [
        "com.microsoft.VSCode": ["vs code", "vscode", "code", "visual studio", "v s code"],
        "com.microsoft.VSCodeInsiders": ["vs code insiders", "code insiders"],
        "com.google.Chrome": ["chrome", "google chrome", "browser"],
        "com.apple.Safari": ["safari"],
        "com.apple.systempreferences": ["settings", "system settings", "system preferences", "preferences", "reglages", "ajustes", "configuracoes"],
        "com.apple.Terminal": ["terminal", "the terminal"],
        "com.googlecode.iterm2": ["iterm", "i term", "iterm2", "iterm 2"],
        "dev.warp.Warp-Stable": ["warp"],
        "com.microsoft.Word": ["word"], "com.microsoft.Excel": ["excel"], "com.microsoft.Powerpoint": ["powerpoint", "power point"],
        "com.microsoft.Outlook": ["outlook"], "com.microsoft.teams2": ["teams", "microsoft teams"], "com.microsoft.teams": ["teams"],
        "com.apple.MobileSMS": ["messages", "imessage", "i message", "texts"], "com.apple.FaceTime": ["facetime", "face time"],
        "com.apple.Music": ["music", "apple music", "itunes"], "com.apple.mail": ["mail", "apple mail", "email app"],
        "com.apple.iCal": ["calendar", "ical", "calendrier", "calendario"], "com.apple.Notes": ["notes", "apple notes"],
        "com.apple.reminders": ["reminders", "rappels", "lembretes"], "com.apple.finder": ["finder"],
        "com.apple.ActivityMonitor": ["activity monitor", "task manager"], "com.apple.Photos": ["photos", "photo app"],
        "com.apple.Preview": ["preview"], "com.apple.AppStore": ["app store", "appstore"], "com.apple.calculator": ["calculator", "calc", "calculatrice", "calculadora"],
        "com.apple.Maps": ["maps", "apple maps", "plans", "mapas"], "net.whatsapp.WhatsApp": ["whatsapp", "whats app"],
        "us.zoom.xos": ["zoom"], "com.tinyspeck.slackmacgap": ["slack"], "com.spotify.client": ["spotify", "spotty", "spot ify"],
        "company.thebrowser.Browser": ["arc", "arc browser"], "com.brave.Browser": ["brave"], "org.mozilla.firefox": ["firefox"],
        "com.microsoft.edgemac": ["edge", "microsoft edge"], "com.apple.dt.Xcode": ["xcode", "x code"],
        "md.obsidian": ["obsidian"], "notion.id": ["notion"], "com.figma.Desktop": ["figma"], "com.hnc.Discord": ["discord"],
        "com.anthropic.claudefordesktop": ["claude", "claude app"], "com.openai.chat": ["chatgpt", "chat gpt"],
        "com.todesktop.230313mzl4w4u92": ["cursor"], "ru.keepcoder.Telegram": ["telegram"], "com.apple.TextEdit": ["textedit", "text edit"],
        "com.apple.Passwords": ["passwords"], "com.apple.Home": ["home app"], "com.apple.weather": ["weather app"],
        "com.1password.1password": ["1password", "one password"],
    ]

    /// Levenshtein distance over characters (names are short, so the plain table is fine).
    public static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
