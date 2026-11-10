import Foundation

/// One decision for a short ask, shared by voice, the menu bar, and `zeus`.
/// A spoken, file, or fast-command result never calls a model.
public enum InstantRoute: Equatable, Sendable {
    case spoken(String)
    case files(query: String)
    case page
    case web(query: String)
    case mixed(command: String, rest: String)
    case fastCommand
    case brain
}

public enum InstantTable {
    /// An instant answer has to be back before a person notices the wait.
    public static let latencyBudgetMs = 150

    public static func route(_ text: String, now: Date = Date(), timeZone: TimeZone = .current) -> InstantRoute {
        if let spoken = spokenAnswer(for: text, now: now, timeZone: timeZone) { return .spoken(spoken) }
        // A command plus a leftover question stays mixed. Page and web reads are checked after, so
        // "open Notes and summarize this" is not swallowed by the page rule.
        if let split = splitMixed(text) { return .mixed(command: split.command, rest: split.rest) }
        if let kind = LocalLookup.kind(in: text) {
            switch kind {
            case .files(let query): return .files(query: query)
            case .page: return .page
            case .web(let query): return .web(query: query)
            }
        }
        if FastIntent.parse(text) != nil { return .fastCommand }
        return .brain
    }

    public static func spokenAnswer(for transcript: String, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        let key = Utterance(transcript).words.joined(separator: " ")
        guard !key.isEmpty else { return nil }
        if matchesCapabilities(key) {
            return "Voice, dictation, agents, your day in the notch, and whatever you point at on screen."
        }
        if matchesTime(key) { return timeAnswer(now: now, timeZone: timeZone) }
        if matchesDate(key) { return dateAnswer(now: now, timeZone: timeZone) }
        if let math = PersonaArithmetic.answer(for: transcript) { return math }
        return nil
    }

    /// Page and web reads use text. A screenshot is the wrong source for them.
    public static func allowsScreenshots(_ route: InstantRoute) -> Bool {
        switch route {
        case .page, .web: return false
        default: return true
        }
    }

    /// One line for `zeus debug brain-route`, with no model call.
    public static func describe(_ text: String, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        switch route(text, now: now, timeZone: timeZone) {
        case .spoken: return "instant spoken"
        case .files(let query): return "instant files \(query)"
        case .page: return "instant page"
        case .web(let query): return "instant web \(query)"
        case .mixed(let command, let rest): return "instant mixed \(command) || \(rest)"
        case .fastCommand: return "instant fast"
        case .brain: return "brain"
        }
    }

    public static func splitMixed(_ text: String) -> (command: String, rest: String)? {
        guard FastIntent.parse(text) == nil else { return nil }
        let folded = text.lowercased()
        for separator in [" and then ", " and "] {
            guard let range = folded.range(of: separator) else { continue }
            let command = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty, !rest.isEmpty, FastIntent.parse(command) != nil, FastIntent.parse(rest) == nil else { continue }
            return (command, rest)
        }
        return nil
    }

    public static func timeAnswer(now: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: now) + "."
    }

    public static func dateAnswer(now: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter.string(from: now) + "."
    }

    private static func matchesCapabilities(_ key: String) -> Bool {
        key.contains("what can you do") || key.contains("what do you do")
            || (key.contains("help") && (key.contains("can you") || key.hasSuffix("help me")))
    }

    private static func matchesTime(_ key: String) -> Bool {
        // Apostrophes are already folded ("what's" → "what"), so match the words that remain.
        key == "time" || key.contains("what time") || key.contains("what the time") || key.contains("what is the time")
            || key.contains("tell me the time") || key.contains("current time")
    }

    private static func matchesDate(_ key: String) -> Bool {
        key.contains("what day") || key.contains("what the date") || key.contains("what is the date")
            || key.contains("today date") || key == "date"
    }
}

/// Files, the page in front, and a web read. Text only: never a screenshot.
public enum LocalLookup {
    public enum Kind: Equatable, Sendable {
        case files(String)
        case page
        case web(String)
    }

    public static func kind(in text: String) -> Kind? {
        var utterance = Utterance(text)
        utterance.stripFiller()
        let key = utterance.words.joined(separator: " ")
        guard !key.isEmpty else { return nil }
        if isPage(key) { return .page }
        if let query = fileQuery(key) { return .files(query) }
        if let query = webQuery(key) { return .web(query) }
        return nil
    }

    public static func isPage(_ key: String) -> Bool {
        if key.contains("summarize this") || key.contains("sum up this") || key.contains("read this article") { return true }
        let aboutPage = key.contains("this article") || key.contains("this page") || key.contains("this tab")
            || key.contains("the article") || key.contains("the page")
        let verb = key.contains("summarize") || key.contains("summary") || key.contains("sum up") || key.contains("read")
        return aboutPage && verb
    }
}

extension LocalLookup {
    static func fileQuery(_ key: String) -> String? {
        let leads = [
            "find my notes about ", "find my notes on ", "find notes about ", "find my note about ",
            "find my files about ", "find my file about ", "find the file named ", "find the file called ",
            "search my files for ", "search my notes for ", "look for my notes about ", "find my documents about ",
        ]
        for lead in leads {
            guard let range = key.range(of: lead) else { continue }
            var query = String(key[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if query.hasPrefix("the ") { query.removeFirst(4) }
            if !query.isEmpty { return query }
        }
        return nil
    }

    static func webQuery(_ key: String) -> String? {
        if let url = firstURL(in: key) { return url }
        let leads = ["search the web for ", "search web for ", "look up ", "google "]
        for lead in leads {
            guard let range = key.range(of: lead) else { continue }
            let query = String(key[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !query.isEmpty { return query }
        }
        return nil
    }

    private static func firstURL(in key: String) -> String? {
        key.split(separator: " ").map(String.init).first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }
}

/// Spotlight query and which hit to open. The process that runs `mdfind` lives in the app.
public enum SpotlightQuery {
    public static func expression(for query: String) -> String {
        let words = query.split(separator: " ").map { token in
            String(token).filter { $0.isLetter || $0.isNumber }
        }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return "kMDItemDisplayName == '*'c" }
        let name = words.map { "kMDItemDisplayName == '*\($0)*'c" }.joined(separator: " && ")
        let body = words.map { "kMDItemTextContent == '*\($0)*'cd" }.joined(separator: " && ")
        return "(\(name)) || (\(body))"
    }

    public static func pick(paths: [String], query: String) -> String? {
        let needles = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        return paths.max { score($0, needles) < score($1, needles) }
    }

    private static func score(_ path: String, _ needles: [String]) -> Int {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
        return needles.reduce(0) { total, needle in
            if name.contains(needle) { return total + 2 }
            if path.lowercased().contains(needle) { return total + 1 }
            return total
        }
    }
}

/// Play resumes a paused session in place. Otherwise Spotify, when it is installed.
public enum MediaPlayPolicy {
    public enum Choice: Equatable, Sendable { case mediaKey, resumeSpotify }

    /// A session that is already playing or paused stays on the media key. Spotify is only the fallback when nothing is loaded.
    public static func choose(hasSession: Bool, spotifyInstalled: Bool) -> Choice {
        if hasSession { return .mediaKey }
        if spotifyInstalled { return .resumeSpotify }
        return .mediaKey
    }
}
