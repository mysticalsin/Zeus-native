import CoreFoundation
import Foundation

/// One JSON object per line between the now-playing helper and Zeus. Version 1.
/// A line longer than `SystemSourceLine.maxBytes`, an unknown name, or a value of
/// the wrong kind is refused whole. Numbers that are not finite refuse the line,
/// except a missing or non-finite duration, which is 0. A negative number is 0.
public enum SystemSourceLine: Equatable, Sendable {
    /// 1 MiB. A longer line is refused before it is parsed.
    public static let maxBytes = 1024 * 1024

    case hello(version: Int, missing: Int)
    case item(SystemSourceItem)
    case none(sequence: Int)
    case art(key: String, jpeg: Data)
    case ack(id: Int, ok: Bool, why: SystemSourceAckWhy?)
    case pong(id: Int)
    case read(id: Int)
    case ping(id: Int)
    case command(id: Int, command: SystemSourceCommand)

    public static func decode(_ line: Data) -> SystemSourceLine? {
        guard line.count <= maxBytes, let text = String(data: line, encoding: .utf8) else { return nil }
        let prepared = SystemSourceJSON.neutralizeNonFiniteNumbers(text)
        guard let data = prepared.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = SystemSourceJSON.dictionary(object),
              let name = SystemSourceJSON.string(fields["t"]) else { return nil }
        switch name {
        case "hello":
            guard SystemSourceJSON.whole(fields["v"]) == 1, let missing = SystemSourceJSON.whole(fields["missing"]) else {
                return nil
            }
            return .hello(version: 1, missing: missing)
        case "item":
            guard let item = SystemSourceItem(fields) else { return nil }
            return .item(item)
        case "none":
            guard let sequence = SystemSourceJSON.whole(fields["seq"]) else { return nil }
            return .none(sequence: sequence)
        case "art":
            guard let key = SystemSourceJSON.string(fields["key"]), !key.isEmpty,
                  let encoded = SystemSourceJSON.string(fields["jpeg"]),
                  let jpeg = Data(base64Encoded: encoded) else { return nil }
            return .art(key: key, jpeg: jpeg)
        case "ack":
            guard let id = SystemSourceJSON.whole(fields["id"]),
                  let ok = SystemSourceJSON.bool(fields["ok"]) else { return nil }
            switch SystemSourceAckWhy.read(fields["why"]) {
            case .bad:
                return nil
            case .absent:
                return .ack(id: id, ok: ok, why: nil)
            case .value(let why):
                return .ack(id: id, ok: ok, why: why)
            }
        case "pong":
            guard let id = SystemSourceJSON.whole(fields["id"]) else { return nil }
            return .pong(id: id)
        case "read":
            guard let id = SystemSourceJSON.whole(fields["id"]) else { return nil }
            return .read(id: id)
        case "ping":
            guard let id = SystemSourceJSON.whole(fields["id"]) else { return nil }
            return .ping(id: id)
        case "cmd":
            guard let id = SystemSourceJSON.whole(fields["id"]),
                  let command = SystemSourceCommand(fields) else { return nil }
            return .command(id: id, command: command)
        default:
            return nil
        }
    }
}

public struct SystemSourceItem: Equatable, Sendable {
    public var sequence: Int
    public var app: String
    public var parent: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Double
    public var elapsed: Double
    public var at: Double
    public var rate: Double
    public var playing: Bool
    public var key: String

    public init(sequence: Int, app: String, parent: String, title: String, artist: String, album: String,
                duration: Double, elapsed: Double, at: Double, rate: Double, playing: Bool, key: String) {
        self.sequence = sequence
        self.app = app
        self.parent = parent
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.at = at
        self.rate = rate
        self.playing = playing
        self.key = key
    }

    init?(_ fields: [String: Any]) {
        guard let sequence = SystemSourceJSON.whole(fields["seq"]),
              let app = SystemSourceJSON.bundleIdentifier(fields["app"]),
              let parent = SystemSourceJSON.bundleIdentifier(fields["parent"]),
              let title = SystemSourceJSON.cleaned(fields["title"]), !title.isEmpty,
              let artist = SystemSourceJSON.optionalCleaned(fields["artist"]),
              let album = SystemSourceJSON.optionalCleaned(fields["album"]),
              let duration = SystemSourceJSON.duration(fields["duration"]),
              let elapsed = SystemSourceJSON.measure(fields["elapsed"]),
              let at = SystemSourceJSON.measure(fields["at"]),
              let rate = SystemSourceJSON.measure(fields["rate"]),
              let playing = SystemSourceJSON.bool(fields["playing"]),
              let key = SystemSourceJSON.string(fields["key"]), !key.isEmpty else { return nil }
        self.init(sequence: sequence, app: app, parent: parent, title: title, artist: artist, album: album,
                  duration: duration, elapsed: elapsed, at: at, rate: rate, playing: playing, key: key)
    }
}

public enum SystemSourceAckWhy: String, Equatable, Sendable {
    case stale, failed

    enum Read {
        case absent
        case value(SystemSourceAckWhy)
        case bad
    }

    static func read(_ value: Any?) -> Read {
        guard let value, !(value is NSNull) else { return .absent }
        guard let text = SystemSourceJSON.string(value) else { return .bad }
        if text.isEmpty { return .absent }
        guard let why = SystemSourceAckWhy(rawValue: text) else { return .bad }
        return .value(why)
    }
}

public struct SystemSourceCommand: Equatable, Sendable {
    public enum Name: String, Equatable, Sendable {
        case play, pause, next, previous, seek
    }

    public var name: Name
    public var seconds: Double
    public var app: String

    public init(name: Name, seconds: Double, app: String) {
        self.name = name
        self.seconds = seconds
        self.app = app
    }

    init?(_ fields: [String: Any]) {
        guard let rawName = SystemSourceJSON.string(fields["name"]),
              let name = Name(rawValue: rawName),
              let seconds = SystemSourceJSON.measure(fields["seconds"]),
              let app = SystemSourceJSON.bundleIdentifier(fields["app"]) else { return nil }
        self.init(name: name, seconds: seconds, app: app)
    }

    /// The `cmd` line for this command, with `id` written into it.
    /// A negative id is 0. A negative or non-finite `seconds` is 0.
    public func line(id: Int) -> Data {
        let safeID = id < 0 ? 0 : id
        let safeSeconds = seconds.isFinite && seconds >= 0 ? seconds : 0
        let object: [String: Any] = [
            "t": "cmd",
            "id": safeID,
            "name": name.rawValue,
            "seconds": safeSeconds,
            "app": app,
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}

public enum SystemSourceText {
    public static let maxCharacters = 300

    /// Line breaks become spaces. Controls and direction overrides are removed.
    /// The result keeps at most 300 extended grapheme clusters, and never splits one.
    public static func clean(_ raw: String) -> String {
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(raw.unicodeScalars.count)
        for scalar in raw.unicodeScalars {
            if lineBreaks.contains(scalar) {
                scalars.append(" ")
            } else if directionOverrides.contains(scalar) || scalar.properties.generalCategory == .control {
                continue
            } else {
                scalars.append(scalar)
            }
        }
        let cleaned = String(String.UnicodeScalarView(scalars))
        return String(cleaned.prefix(maxCharacters))
    }

    private static let lineBreaks: Set<Unicode.Scalar> = ["\n", "\r", "\u{2028}", "\u{2029}"]
    private static let directionOverrides: Set<Unicode.Scalar> = [
        "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
    ]
}

enum SystemSourceJSON {
    static func neutralizeNonFiniteNumbers(_ raw: String) -> String {
        let scalars = Array(raw.unicodeScalars)
        var out = ""
        out.reserveCapacity(raw.count)
        var inString = false
        var escaped = false
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if inString {
                out.unicodeScalars.append(scalar)
                if escaped {
                    escaped = false
                } else if scalar == "\\" {
                    escaped = true
                } else if scalar == "\"" {
                    inString = false
                }
                index += 1
                continue
            }
            if scalar == "\"" {
                inString = true
                out.unicodeScalars.append(scalar)
                index += 1
                continue
            }
            if let length = nonFiniteTokenLength(scalars, index) {
                out += "null"
                index += length
                continue
            }
            out.unicodeScalars.append(scalar)
            index += 1
        }
        return out
    }

    static func dictionary(_ object: Any) -> [String: Any]? {
        if let typed = object as? [String: Any] { return typed }
        guard let ns = object as? NSDictionary else { return nil }
        var result: [String: Any] = [:]
        result.reserveCapacity(ns.count)
        for (key, value) in ns {
            guard let name = key as? String else { return nil }
            result[name] = value
        }
        return result
    }

    static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let text = value as? String { return text }
        if let text = value as? NSString { return text as String }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        guard let value, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        if value is NSNumber { return nil }
        if let flag = value as? Bool { return flag }
        return nil
    }

    /// A finite whole number. A negative number is 0. Anything else is refused.
    static func whole(_ value: Any?) -> Int? {
        switch number(value) {
        case .finite(let raw):
            guard raw <= Double(Int.max), raw >= Double(Int.min) else { return nil }
            guard raw.rounded(.towardZero) == raw else { return nil }
            let int = Int(raw)
            return int < 0 ? 0 : int
        case .missing, .nonFinite, .bad:
            return nil
        }
    }

    /// A required finite measure. A negative number is 0.
    static func measure(_ value: Any?) -> Double? {
        switch number(value) {
        case .finite(let raw):
            return raw < 0 ? 0 : raw
        case .missing, .nonFinite, .bad:
            return nil
        }
    }

    /// Missing and non-finite durations are 0. A negative duration is 0. A value of the wrong kind is refused.
    static func duration(_ value: Any?) -> Double? {
        switch number(value) {
        case .missing, .nonFinite:
            return 0
        case .finite(let raw):
            return raw < 0 ? 0 : raw
        case .bad:
            return nil
        }
    }

    static func cleaned(_ value: Any?) -> String? {
        guard let text = string(value) else { return nil }
        return SystemSourceText.clean(text)
    }

    static func optionalCleaned(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return "" }
        return cleaned(value)
    }

    static func bundleIdentifier(_ value: Any?) -> String? {
        guard let text = string(value), isBundleIdentifier(text) else { return nil }
        return text
    }

    static func isBundleIdentifier(_ text: String) -> Bool {
        guard (1...155).contains(text.count) else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            (scalar >= "a" && scalar <= "z")
                || (scalar >= "A" && scalar <= "Z")
                || (scalar >= "0" && scalar <= "9")
                || scalar == "."
                || scalar == "-"
        }
    }

    private enum Number {
        case missing
        case finite(Double)
        case nonFinite
        case bad
    }

    private static func number(_ value: Any?) -> Number {
        guard let value else { return .missing }
        if value is NSNull { return .missing }
        let raw: Double
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bad }
            raw = number.doubleValue
        } else if let number = value as? Double {
            raw = number
        } else if let number = value as? Int {
            raw = Double(number)
        } else {
            return .bad
        }
        return raw.isFinite ? .finite(raw) : .nonFinite
    }

    private static func nonFiniteTokenLength(_ scalars: [Unicode.Scalar], _ index: Int) -> Int? {
        for token in ["-Infinity", "+Infinity", "Infinity", "NaN"] {
            let tokenScalars = Array(token.unicodeScalars)
            let end = index + tokenScalars.count
            guard end <= scalars.count else { continue }
            guard Array(scalars[index..<end]) == tokenScalars else { continue }
            if index > 0, isTokenBody(scalars[index - 1]) { continue }
            if end < scalars.count, isTokenBody(scalars[end]) { continue }
            return tokenScalars.count
        }
        return nil
    }

    private static func isTokenBody(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "a" && scalar <= "z")
            || (scalar >= "A" && scalar <= "Z")
            || (scalar >= "0" && scalar <= "9")
            || scalar == "_"
    }
}
