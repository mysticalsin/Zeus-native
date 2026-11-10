import Foundation

/// "lunch with Ana tomorrow at 1 pm", "déjeuner avec Ana demain à 13h", "almoço com a Ana amanhã às 13h":
/// the event's title and when it starts. Pure and deterministic (no network, no model); English, French
/// and Portuguese. The to-do date parser only yields a due day, so events get their own.
public enum CalendarQuickAdd {
    public struct Parsed: Equatable, Sendable {
        public var title: String
        public var start: Date
        public var end: Date
        public var isAllDay: Bool
        /// The text named a day or a time (a voice rule only acts when it did).
        public var hadDate: Bool
    }

    /// An hour on the 12-hour clock with no am/pm ("at 9", "at 1:30") reads as afternoon up to 6.
    static let afternoonCutoff = 6
    static let defaultMinutes = 60

    // MARK: Vocabulary (normalised: lower case, accents folded)

    static let leadVerbs: Set<String> = ["add", "create", "schedule", "book", "put", "new", "set",
                                         "ajoute", "ajouter", "cree", "creer", "planifie", "planifier", "programme", "programmer", "fixe",
                                         "adiciona", "adicione", "adicionar", "cria", "crie", "criar", "agenda", "agende", "agendar", "marca", "marque", "marcar"]
    static let leadFiller: Set<String> = ["a", "an", "the", "un", "une", "o", "um", "uma", "novo", "nova", "nouvel", "nouveau", "nouvelle", "up", "me"]
    static let eventNouns: Set<String> = ["event", "meeting", "appointment", "evenement", "rendez-vous", "reunion", "evento", "reuniao", "compromisso", "consulta"]
    static let connectors: Set<String> = ["with", "avec", "com", "about", "for", "pour", "para", "on", "at", "to", "de", "du", "sur", "sobre", "in", "em", "a", "as", "tomorrow", "today", "demain", "amanha", "hoje"]
    static let namedWords: Set<String> = ["called", "named", "titled", "intitule", "nomme", "chamado", "chamada"]
    static let calendarPhrases: [[String]] = [
        "to my calendar", "in my calendar", "on my calendar", "to the calendar", "in the calendar", "on the calendar", "to calendar",
        "a mon calendrier", "dans mon calendrier", "sur mon calendrier", "a mon agenda", "dans mon agenda", "sur mon agenda",
        "no meu calendario", "ao meu calendario", "na minha agenda", "na agenda", "no calendario", "a minha agenda",
    ].map { $0.split(separator: " ").map(String.init) }
    static let preps: Set<String> = ["on", "at", "for", "by", "the", "this", "next", "le", "la", "a", "au", "pour", "vers", "em", "no", "na", "as", "para", "dia", "de", "do", "da", "du", "in", "to", "ce", "cette"]

    static let today: Set<String> = ["today", "aujourd'hui", "hoje"]
    static let tonight: [[String]] = [["tonight"], ["ce", "soir"], ["hoje", "a", "noite"], ["esta", "noite"]]
    static let tomorrow: Set<String> = ["tomorrow", "demain", "amanha"]
    static let afterTomorrow: [[String]] = [["day", "after", "tomorrow"], ["apres-demain"], ["apres", "demain"], ["depois", "de", "amanha"]]
    static let weekdays: [(Int, Set<String>)] = [
        (1, ["sunday", "dimanche", "domingo"]), (2, ["monday", "lundi", "segunda", "segunda-feira"]),
        (3, ["tuesday", "mardi", "terca", "terca-feira"]), (4, ["wednesday", "mercredi", "quarta", "quarta-feira"]),
        (5, ["thursday", "jeudi", "quinta", "quinta-feira"]), (6, ["friday", "vendredi", "sexta", "sexta-feira"]),
        (7, ["saturday", "samedi", "sabado"]),
    ]
    static let months: [(Int, Set<String>)] = [
        (1, ["january", "janvier", "janeiro"]), (2, ["february", "fevrier", "fevereiro"]), (3, ["march", "mars", "marco"]),
        (4, ["april", "avril", "abril"]), (5, ["may", "mai", "maio"]), (6, ["june", "juin", "junho"]),
        (7, ["july", "juillet", "julho"]), (8, ["august", "aout", "agosto"]), (9, ["september", "septembre", "setembro"]),
        (10, ["october", "octobre", "outubro"]), (11, ["november", "novembre", "novembro"]), (12, ["december", "decembre", "dezembro"]),
    ]
    static let noon: [[String]] = [["noon"], ["midi"], ["meio-dia"], ["meio", "dia"]]
    static let midnight: [[String]] = [["midnight"], ["minuit"], ["meia-noite"], ["meia", "noite"]]
    static let atWords: Set<String> = ["at", "a", "as", "vers", "around", "@"]
    static let hourUnits: Set<String> = ["hour", "hours", "hr", "hrs", "heure", "heures", "hora", "horas"]
    static let minuteUnits: Set<String> = ["minute", "minutes", "min", "mins", "minuto", "minutos"]
    static let dayUnits: Set<String> = ["day", "days", "jour", "jours", "dia", "dias"]
    static let weekUnits: Set<String> = ["week", "weeks", "semaine", "semaines", "semana", "semanas"]

    // MARK: Parse

    /// The event in `text`, or nil when no title is left. With no day and no time the event starts at the
    /// next whole hour (`hadDate` false); a day alone makes it an all-day event.
    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Parsed? {
        var utterance = Utterance(text)
        utterance.stripFiller()
        let words = utterance.words
        let original = utterance.original
        guard !words.isEmpty else { return nil }
        var used = Set<Int>()
        var strippedNoun: String?

        // Leading command: "add", "schedule a meeting called".
        if leadVerbs.contains(words[0]) {
            var head = 1
            while head < words.count, leadFiller.contains(words[head]) { head += 1 }
            // "schedule a meeting called Roadmap" and "create an event dentist" drop the noun; "a meeting with Sam" keeps it as the title.
            if head + 1 < words.count, eventNouns.contains(words[head]), !connectors.contains(words[head + 1]) {
                strippedNoun = original[head]
                head += 1
                if namedWords.contains(words[head]), head + 1 < words.count { head += 1 }
            }
            if head >= words.count { return nil }
            used.formUnion(0..<head)
        }
        // "to my calendar" anywhere.
        for phrase in calendarPhrases {
            if let index = find(phrase, in: words, skipping: used) { used.formUnion(index..<(index + phrase.count)); break }
        }

        var day: Date?
        var dayDefaultHour: Int?
        var time: (hour: Int, minute: Int)?
        var absolute: Date?
        var minutes = defaultMinutes
        var matched = Set<Int>()

        var i = 0
        while i < words.count {
            if used.contains(i) { i += 1; continue }
            if day == nil, absolute == nil, let found = matchDay(words, at: i, now: now, calendar: calendar) {
                day = found.date; dayDefaultHour = found.defaultHour
                matched.formUnion(i..<(i + found.length)); i += found.length
                continue
            }
            if day == nil, absolute == nil, let found = matchRelative(words, at: i, now: now, calendar: calendar) {
                if found.isTime { absolute = found.date } else { day = found.date }
                matched.formUnion(i..<(i + found.length)); i += found.length
                continue
            }
            if time == nil, absolute == nil, let found = matchTime(words, at: i) {
                time = (found.hour, found.minute)
                matched.formUnion(i..<(i + found.length)); i += found.length
                continue
            }
            if let found = matchDuration(words, at: i) {
                minutes = found.minutes
                used.formUnion(i..<(i + found.length)); i += found.length
                continue
            }
            i += 1
        }
        // A leading preposition of a matched day or time goes with it ("on friday", "à 13h").
        for index in matched.sorted() where index > 0 && !matched.contains(index - 1) && !used.contains(index - 1) && preps.contains(words[index - 1]) {
            used.insert(index - 1)
        }
        used.formUnion(matched)

        var title = (0..<words.count).filter { !used.contains($0) }.map { original[$0] }
        // A dangling preposition at either end ("lunch with Ana on").
        while let last = title.last, preps.contains(Utterance.normalize(last)) || last == "-" { title.removeLast() }
        while let first = title.first, ["-", ":"].contains(first) { title.removeFirst() }
        let cleaned = title.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // "add meeting friday at 2": the noun is all the title there is.
        let fallback = cleaned.isEmpty ? (strippedNoun ?? "") : cleaned
        guard !fallback.isEmpty else { return nil }
        let name = fallback.prefix(1).uppercased() + fallback.dropFirst()

        let hadDate = day != nil || time != nil || absolute != nil
        var start: Date
        var allDay = false
        if let absolute {
            start = absolute
        } else if let day {
            let base = calendar.startOfDay(for: day)
            if let time {
                start = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base) ?? base
            } else if let dayDefaultHour {
                start = calendar.date(bySettingHour: dayDefaultHour, minute: 0, second: 0, of: base) ?? base
            } else {
                start = base
                allDay = true
            }
        } else if let time {
            let base = calendar.startOfDay(for: now)
            start = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base) ?? base
            if start <= now { start = calendar.date(byAdding: .day, value: 1, to: start) ?? start }
        } else {
            start = nextWholeHour(after: now, calendar: calendar)
        }
        let end = allDay ? (calendar.date(byAdding: .day, value: 1, to: start) ?? start) : start.addingTimeInterval(Double(minutes) * 60)
        return Parsed(title: name, start: start, end: end, isAllDay: allDay, hadDate: hadDate)
    }

    static func nextWholeHour(after now: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let floor = calendar.date(from: parts) ?? now
        return calendar.date(byAdding: .hour, value: 1, to: floor) ?? now
    }

    // MARK: Matching

    private static func find(_ phrase: [String], in words: [String], skipping used: Set<Int>) -> Int? {
        guard phrase.count <= words.count else { return nil }
        for start in 0...(words.count - phrase.count) where Array(words[start..<(start + phrase.count)]) == phrase {
            if !(start..<(start + phrase.count)).contains(where: used.contains) { return start }
        }
        return nil
    }

    private static func has(_ phrases: [[String]], _ words: [String], at i: Int) -> Int? {
        phrases.first { i + $0.count <= words.count && Array(words[i..<(i + $0.count)]) == $0 }?.count
    }

    private static func addDays(_ n: Int, to now: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: n, to: calendar.startOfDay(for: now)) ?? now
    }

    private struct DayMatch { var date: Date; var length: Int; var defaultHour: Int? }

    private static func matchDay(_ words: [String], at i: Int, now: Date, calendar: Calendar) -> DayMatch? {
        let word = words[i]
        if let n = has(afterTomorrow, words, at: i) { return DayMatch(date: addDays(2, to: now, calendar), length: n, defaultHour: nil) }
        if let n = has(tonight, words, at: i) { return DayMatch(date: addDays(0, to: now, calendar), length: n, defaultHour: 19) }
        if today.contains(word) { return DayMatch(date: addDays(0, to: now, calendar), length: 1, defaultHour: nil) }
        if tomorrow.contains(word) { return DayMatch(date: addDays(1, to: now, calendar), length: 1, defaultHour: nil) }
        // Weekday: "friday", "lundi prochain", "sexta que vem".
        if let weekday = weekdays.first(where: { $0.1.contains(word) })?.0 {
            var length = 1
            if i + 1 < words.count, ["prochain", "proxima", "proximo"].contains(words[i + 1]) { length = 2 }
            else if i + 2 < words.count, words[i + 1] == "que", words[i + 2] == "vem" { length = 3 }
            let current = calendar.component(.weekday, from: now)
            var ahead = (weekday - current + 7) % 7
            if ahead == 0 { ahead = 7 }
            return DayMatch(date: addDays(ahead, to: now, calendar), length: length, defaultHour: nil)
        }
        if word.count == 10, TodoMarkdown.isDay(word), let date = TodoQuickAdd.day(word, calendar: calendar) {
            return DayMatch(date: calendar.startOfDay(for: date), length: 1, defaultHour: nil)
        }
        // "november 5", "5 november", "5th of november", "5 de novembro".
        if let month = months.first(where: { $0.1.contains(word) })?.0, i + 1 < words.count, let d = dayNumber(words[i + 1]) {
            return dated(month: month, day: d, length: 2, now: now, calendar: calendar)
        }
        if let d = dayNumber(word) {
            var j = i + 1
            while j < words.count, ["of", "de", "d'", "do"].contains(words[j]) { j += 1 }
            if j < words.count, let month = months.first(where: { $0.1.contains(words[j]) })?.0 {
                return dated(month: month, day: d, length: j - i + 1, now: now, calendar: calendar)
            }
        }
        return nil
    }

    private static func dayNumber(_ word: String) -> Int? {
        var digits = word
        for suffix in ["st", "nd", "rd", "th", "er"] where digits.hasSuffix(suffix) && digits.count > suffix.count { digits = String(digits.dropLast(suffix.count)); break }
        guard digits.allSatisfy(\.isNumber), let n = Int(digits), (1...31).contains(n) else { return nil }
        return n
    }

    private static func dated(month: Int, day: Int, length: Int, now: Date, calendar: Calendar) -> DayMatch? {
        let year = calendar.component(.year, from: now)
        let startToday = calendar.startOfDay(for: now)
        for y in [year, year + 1] {
            if let date = calendar.date(from: DateComponents(year: y, month: month, day: day)),
               calendar.component(.month, from: date) == month, date >= startToday {
                return DayMatch(date: date, length: length, defaultHour: nil)
            }
        }
        return nil
    }

    /// "in 2 days", "in 3 hours", "dans 2 jours", "daqui a 2 horas", "em 2 dias".
    private static func matchRelative(_ words: [String], at i: Int, now: Date, calendar: Calendar) -> (date: Date, length: Int, isTime: Bool)? {
        var j = i
        if words[i] == "daqui", i + 1 < words.count, words[i + 1] == "a" { j = i + 2 }
        else if ["in", "dans", "em"].contains(words[i]) { j = i + 1 }
        else { return nil }
        guard j + 1 < words.count, let n = Int(words[j]), n > 0, n <= 400 else { return nil }
        let unit = words[j + 1]
        let length = j + 2 - i
        if dayUnits.contains(unit) { return (addDays(n, to: now, calendar), length, false) }
        if weekUnits.contains(unit) { return (addDays(7 * n, to: now, calendar), length, false) }
        if hourUnits.contains(unit) { return (now.addingTimeInterval(Double(n) * 3600), length, true) }
        if minuteUnits.contains(unit) { return (now.addingTimeInterval(Double(n) * 60), length, true) }
        return nil
    }

    private static let clock = try! NSRegularExpression(pattern: #"^(\d{1,2})(?:[:.h](\d{2})?)?(am|pm|a\.m|p\.m)?$"#)

    private struct TimeMatch { var hour: Int; var minute: Int; var length: Int }

    private static func matchTime(_ words: [String], at i: Int) -> TimeMatch? {
        if let n = has(noon, words, at: i) { return TimeMatch(hour: 12, minute: 0, length: n) }
        if let n = has(midnight, words, at: i) { return TimeMatch(hour: 0, minute: 0, length: n) }
        let word = words[i]
        guard word.first?.isNumber == true else { return nil }
        let range = NSRange(word.startIndex..., in: word)
        guard let match = clock.firstMatch(in: word, range: range), let hourRange = Range(match.range(at: 1), in: word),
              var hour = Int(word[hourRange]) else { return nil }
        var minute = 0
        if let r = Range(match.range(at: 2), in: word) { minute = Int(word[r]) ?? 0 }
        var marker = Range(match.range(at: 3), in: word).map { String(word[$0]) }
        var length = 1
        // "1 pm", "1 p.m".
        if marker == nil, i + 1 < words.count, ["am", "pm", "a.m", "p.m"].contains(words[i + 1]) { marker = words[i + 1]; length = 2 }
        let hMark = word.contains("h")
        let separator = word.contains(":") || word.contains(".") || hMark
        // A bare number is a time only after "at" ("at 9"); "5 minutes" and "2 people" are not.
        if !separator, marker == nil {
            guard i > 0, atWords.contains(words[i - 1]),
                  !(i + 1 < words.count && (minuteUnits.contains(words[i + 1]) || hourUnits.contains(words[i + 1]))) else { return nil }
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if let marker {
            let pm = marker.hasPrefix("p")
            guard (1...12).contains(hour) else { return nil }
            if pm, hour < 12 { hour += 12 }
            if !pm, hour == 12 { hour = 0 }
        } else if (1...afternoonCutoff).contains(hour), !hMark {
            hour += 12
        }
        return TimeMatch(hour: hour, minute: minute, length: length)
    }

    /// "for 2 hours", "pour 30 minutes", "por 1 hora".
    private static func matchDuration(_ words: [String], at i: Int) -> (minutes: Int, length: Int)? {
        // Bounded to ten years so a typed count can never overflow `n * 60`.
        let limit = 24 * 365 * 10
        guard ["for", "pour", "por", "durante"].contains(words[i]), i + 2 < words.count, let n = Int(words[i + 1]), n > 0, n <= limit else { return nil }
        let unit = words[i + 2]
        if hourUnits.contains(unit) { return (n * 60, 3) }
        if minuteUnits.contains(unit) { return (n, 3) }
        return nil
    }
}
