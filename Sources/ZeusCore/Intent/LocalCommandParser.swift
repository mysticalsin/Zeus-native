import Foundation

/// A command the local machine can carry out without a model.
/// App queries are normalised words, not a chosen installed app.
public enum LocalCommand: Equatable, Sendable {
    case open(String)
    case quit(String)
    case switchTo(String)
    case media(LocalMedia)
    case volume(LocalVolume)
}

public enum LocalMedia: String, Equatable, Sendable {
    case play, pause, next
}

public enum LocalVolume: Equatable, Sendable {
    case up, down, mute, unmute
    case set(Int)
}

/// The closed grammar in `specs/011-fast-local-commands/spec.md`.
/// nil means the words are not a local command.
public enum LocalCommandParser {
    public static func parse(_ text: String) -> LocalCommand? {
        var words = normalize(text).split(separator: " ").map(String.init)
        stripFillers(&words)
        guard !words.isEmpty else { return nil }
        let phrase = words.joined(separator: " ")
        if let media = mediaPhrases[phrase] { return .media(media) }
        if let volume = volumePhrases[phrase] { return .volume(volume) }
        if let set = volumeSet(words) { return .volume(.set(set)) }
        if let query = appQuery(words, verbs: openVerbs) { return .open(query) }
        if let query = appQuery(words, verbs: switchVerbs) { return .switchTo(query) }
        if let query = appQuery(words, verbs: quitVerbs) { return .quit(query) }
        return nil
    }

    // MARK: Words

    /// Lower case, diacritics folded, apostrophes removed, every other non-letter turned into a space.
    public static func normalize(_ text: String) -> String {
        var raw = text.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
        raw = raw.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        raw = raw.replacingOccurrences(of: "'", with: "")
        let mapped = raw.unicodeScalars.map { scalar -> Character in
            if scalar == "%" { return " " }
            return CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    private static let leadingFillers: [[String]] = [
        ["hey", "zeus"], ["hi", "zeus"], ["hello", "zeus"], ["okay", "zeus"], ["ok", "zeus"],
        ["can", "you"], ["could", "you"], ["would", "you"],
        ["please"], ["um"], ["uh"], ["zeus"],
    ]

    private static let trailingFillers: [[String]] = [
        ["for", "me"], ["thank", "you"], ["please"], ["thanks"], ["now"],
    ]

    private static func stripFillers(_ words: inout [String]) {
        var changed = true
        while changed {
            changed = false
            for filler in leadingFillers where words.starts(with: filler) {
                words.removeFirst(filler.count)
                changed = true
            }
            for filler in trailingFillers where words.count >= filler.count && Array(words.suffix(filler.count)) == filler {
                words.removeLast(filler.count)
                changed = true
            }
        }
    }

    // MARK: Media and volume

    private static let mediaPhrases: [String: LocalMedia] = {
        var map: [String: LocalMedia] = [:]
        let play = ["play", "play music", "play the music", "resume", "resume music", "resume the music",
                    "resume playback", "start music", "start the music"]
        let pause = ["pause", "pause music", "pause the music", "pause the song", "pause playback"]
        let next = ["next", "next song", "next track", "skip", "skip song", "skip track", "skip this song", "skip this track"]
        for phrase in play { map[phrase] = .play }
        for phrase in pause { map[phrase] = .pause }
        for phrase in next { map[phrase] = .next }
        return map
    }()

    private static let volumePhrases: [String: LocalVolume] = {
        var map: [String: LocalVolume] = [:]
        for phrase in ["volume up", "louder", "turn it up", "turn the volume up", "turn up the volume"] { map[phrase] = .up }
        for phrase in ["volume down", "quieter", "turn it down", "turn the volume down", "turn down the volume"] { map[phrase] = .down }
        for phrase in ["mute", "mute it"] { map[phrase] = .mute }
        for phrase in ["unmute", "unmute it"] { map[phrase] = .unmute }
        return map
    }()

    private static let volumeHeads: Set<String> = [
        "set the volume to", "set volume to", "set the volume at", "set volume at",
        "change the volume to", "change volume to", "change the volume at",
        "put the volume to", "put the volume at", "put volume to", "put volume at",
        "turn the volume to", "turn the volume at", "turn volume to",
        "make the volume to", "make the volume at",
        "volume to", "volume at", "volume",
    ]

    private static func volumeSet(_ words: [String]) -> Int? {
        var words = words
        if words.last == "percent" { words.removeLast() }
        guard let number = trailingNumber(words), (0...100).contains(number.value) else { return nil }
        let head = words.dropLast(number.count).joined(separator: " ")
        guard volumeHeads.contains(head) else { return nil }
        return number.value
    }

    private static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]

    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// A number occupying the end of `words`: digits, one number word, or a ten plus a one.
    private static func trailingNumber(_ words: [String]) -> (value: Int, count: Int)? {
        guard let last = words.last else { return nil }
        if !last.isEmpty, last.allSatisfy(\.isNumber), let digits = Int(last) {
            return (digits, 1)
        }
        if words.count >= 2, let ten = tens[words[words.count - 2]], let one = ones[last], (1...9).contains(one) {
            return (ten + one, 2)
        }
        if let value = ones[last] { return (value, 1) }
        if let value = tens[last] { return (value, 1) }
        if last == "hundred" { return (100, 1) }
        return nil
    }

    // MARK: Apps

    /// Longer phrases first so "switch to" wins over "switch" and "fire up" wins over nothing shorter.
    private static let openVerbs = ["fire up", "bring up", "pull up", "open", "launch", "start", "run"]
    private static let switchVerbs = ["switch to", "go to", "switch"]
    private static let quitVerbs = ["quit", "close", "exit"]

    private static let blockedQueryWords: Set<String> = [
        "it", "this", "that", "these", "those", "them", "window", "windows", "tab", "tabs", "file", "files",
        "folder", "folders", "everything", "all", "application", "screen", "page", "email", "message", "and", "then",
    ]

    /// The normalised query after `verbs`, or nil when the phrase is not that kind of app command.
    private static func appQuery(_ words: [String], verbs: [String]) -> String? {
        let phrase = words.joined(separator: " ")
        for verb in verbs {
            let rest: String
            if phrase == verb { return nil }
            let prefix = verb + " "
            guard phrase.hasPrefix(prefix) else { continue }
            rest = String(phrase.dropFirst(prefix.count))
            var query = rest.split(separator: " ").map(String.init)
            if query.first == "the" || query.first == "my" { query.removeFirst() }
            if query.last == "app" || query.last == "application" { query.removeLast() }
            guard (1...4).contains(query.count) else { return nil }
            guard !query.contains(where: { blockedQueryWords.contains($0) }) else { return nil }
            let name = query.joined(separator: " ")
            guard name.count >= 2 else { return nil }
            return name
        }
        return nil
    }
}
