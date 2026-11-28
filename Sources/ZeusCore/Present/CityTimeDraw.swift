import Foundation

/// The time in another city, drawn while Zeus says it.
///
/// The voice says the full line. One city builds the name, then the digits, then AM or PM.
/// The world clock builds World, then each city. The wall clock stays on its own card.
public struct CityTimeReading: Equatable, Sendable {
    public var city: String
    public var time: String
    public var period: String

    public init(city: String, time: String, period: String) {
        self.city = city
        self.time = time
        self.period = period
    }
}

public enum CityTimeAsk {
    public static let unknown = "I don't know that city."

    /// The place in "what time is it in Tokyo". Nil for the wall clock, a meeting, or a countdown.
    public static func city(in text: String) -> String? {
        let words = words(in: text)
        let prefixes: [[String]] = [
            ["what", "time", "is", "it", "in"],
            ["what", "is", "the", "time", "in"],
            ["tell", "me", "what", "time", "it", "is", "in"],
            ["tell", "me", "the", "time", "in"],
            ["what", "time", "in"],
            ["current", "time", "in"],
            ["time", "in"],
        ]
        for prefix in prefixes {
            guard words.count > prefix.count, Array(words.prefix(prefix.count)) == prefix else { continue }
            var cityWords = Array(words.dropFirst(prefix.count))
            let tail: Set<String> = ["please", "now", "right", "today", "tomorrow", "thanks"]
            while let last = cityWords.last, tail.contains(last), !cityWords.isEmpty { cityWords.removeLast() }
            if cityWords.first == "the" { cityWords.removeFirst() }
            let durations: Set<String> = ["minute", "minutes", "hour", "hours", "second", "seconds", "min", "mins"]
            guard !cityWords.isEmpty,
                  cityWords.allSatisfy({ $0.allSatisfy(\.isLetter) }),
                  !cityWords.contains(where: { durations.contains($0) }) else { return nil }
            return cityWords.joined(separator: " ")
        }
        return nil
    }

    public static func matches(_ text: String) -> Bool {
        city(in: text) != nil
    }

    /// "2:47" and "AM" in that zone. Hour 0 and 12 are both 12.
    public static func parts(now: Date, timeZone: TimeZone) -> (time: String, period: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let hour24 = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let period = hour24 < 12 ? "AM" : "PM"
        return (String(format: "%d:%02d", hour12, minute), period)
    }

    /// The zone whose city name matches, ignoring case and accents.
    public static func zone(named city: String) -> TimeZone? {
        zones[fold(city)]
    }

    /// "Tokyo" from Asia/Tokyo.
    public static func placeName(for zone: TimeZone) -> String {
        let last = zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Nil when the city, the time, or the period is not a reading.
    public static func line(city: String, time: String, period: String) -> String? {
        guard let city = place(city), let time = clockTime(time), let period = dayPeriod(period) else { return nil }
        return "It's \(time) \(period) in \(city)."
    }

    /// One sentence for the cities on the world clock. Nil when none are readings.
    public static func line(readings: [CityTimeReading]) -> String? {
        let shown = readings.prefix(3).compactMap { reading -> String? in
            guard let city = place(reading.city), let time = clockTime(reading.time), let period = dayPeriod(reading.period) else { return nil }
            return "\(time) \(period) in \(city)"
        }
        guard !shown.isEmpty, shown.count == min(3, readings.count) else { return nil }
        guard let first = shown.first else { return nil }
        if shown.count == 1 { return "It's \(first)." }
        if shown.count == 2 { return "It's \(shown[0]) and \(shown[1])." }
        let head = shown.dropLast().joined(separator: ", ")
        return "It's \(head), and \(shown[shown.count - 1])."
    }

    private static let zones: [String: TimeZone] = {
        var index: [String: TimeZone] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let zone = TimeZone(identifier: identifier) else { continue }
            let key = fold(placeName(for: zone))
            guard !key.isEmpty else { continue }
            if let existing = index[key] {
                if prefer(identifier, over: existing.identifier) { index[key] = zone }
            } else {
                index[key] = zone
            }
        }
        return index
    }()

    private static func prefer(_ candidate: String, over existing: String) -> Bool {
        let candidateParts = candidate.split(separator: "/").count
        let existingParts = existing.split(separator: "/").count
        if candidateParts != existingParts { return candidateParts < existingParts }
        return candidate < existing
    }

    static func place(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(TalkDraw.maxTextCharacters))
    }

    static func clockTime(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(separator: ":")
        guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]),
              (1...12).contains(hour), (0...59).contains(minute), pieces[1].count == 2 else { return nil }
        return String(format: "%d:%02d", hour, minute)
    }

    static func dayPeriod(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "AM": return "AM"
        case "PM": return "PM"
        default: return nil
        }
    }

    private static func fold(_ raw: String) -> String {
        let base = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let spaced = base.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(spaced).split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "what's", with: "what is")
        folded = folded.replacingOccurrences(of: "whats", with: "what is")
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { String($0).replacingOccurrences(of: "'", with: "") }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        return words
    }
}

public struct CityTimeDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var title: String
    public var lines: [String]

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, title: String, lines: [String]) {
        self.draw = draw
        self.schedule = schedule
        self.title = title
        self.lines = lines
    }

    /// Nil when the city or the clock reading is blank.
    public static func plan(city: String, time: String, period: String) -> CityTimeDraw? {
        guard let city = CityTimeAsk.place(city),
              let time = CityTimeAsk.clockTime(time),
              let period = CityTimeAsk.dayPeriod(period) else { return nil }
        return make(title: city, lines: [time, period])
    }

    /// One city uses that city's cards. Several cities use World, then each reading. Nil when none are valid.
    public static func plan(readings: [CityTimeReading]) -> CityTimeDraw? {
        let shown = readings.prefix(3).compactMap { reading -> (String, String, String)? in
            guard let city = CityTimeAsk.place(reading.city),
                  let time = CityTimeAsk.clockTime(reading.time),
                  let period = CityTimeAsk.dayPeriod(reading.period) else { return nil }
            return (city, time, period)
        }
        guard !shown.isEmpty, shown.count == min(3, readings.count) else { return nil }
        if shown.count == 1, let only = shown.first {
            return plan(city: only.0, time: only.1, period: only.2)
        }
        return make(title: "World", lines: shown.map { "\($0.0) \($0.1) \($0.2)" })
    }

    public static func unknown() -> CityTimeDraw {
        make(title: "City", lines: ["Unknown"])
    }

    /// The short line beside the bolt. The first beat names the city, or World.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed + 0.001)
        guard let last = shown.last, last >= 1 else { return title }
        let index = last - 1
        guard lines.indices.contains(index) else { return title }
        return Self.shortLine(lines[index])
    }

    /// Where the bolt sits: the ring first, then the newest card.
    public func guideBolt(at elapsed: TimeInterval) -> TalkDraw.Point? {
        let shown = Set(schedule.revealed(at: elapsed + 0.001))
        let marks = draw.marks.filter { shown.contains($0.at) }
        guard let beat = marks.map(\.at).max() else { return nil }
        let placed = marks.filter { $0.at == beat }.compactMap { mark -> (Int, TalkDraw.Point)? in
            guard let point = Self.anchor(of: mark) else { return nil }
            return (Self.preference(mark), point)
        }
        return placed.min { $0.0 < $1.0 }?.1
    }

    private static func make(title: String, lines: [String]) -> CityTimeDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: title), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return CityTimeDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), title: title, lines: lines)
    }

    private static func shortLine(_ raw: String) -> String {
        var current = ""
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > 40 { break }
            current = next
        }
        let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? String(raw.prefix(40)) : line
    }

    private static func preference(_ mark: TalkDraw.Mark) -> Int {
        switch mark.shape {
        case .ring: return 0
        case .arrow: return 1
        case .ink: return 2
        case .card: return 3
        }
    }

    private static func anchor(of mark: TalkDraw.Mark) -> TalkDraw.Point? {
        switch mark.shape {
        case .ring(let center, let radius):
            guard radius.isFinite, radius > 0, center.x.isFinite, center.y.isFinite else { return nil }
            return center
        case .arrow(let from, let to):
            let point = TalkDraw.Point(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            guard point.x.isFinite, point.y.isFinite else { return nil }
            return point
        case .ink(let points):
            return points.last
        case .card(let origin, _):
            guard origin.x.isFinite, origin.y.isFinite else { return nil }
            return origin
        }
    }
}
