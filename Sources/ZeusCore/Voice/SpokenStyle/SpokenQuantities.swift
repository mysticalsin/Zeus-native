import Foundation

enum SpokenQuantities {
    static func apply(_ draft: SpokenDraft, language: SpokenLanguage) -> SpokenDraft {
        let spoken = expandingUnits(verbalizing(draft.text, language: language), language: language)
        return SpokenDraft(text: SpokenText.collapse(spoken), runs: [])
    }

    private struct NumberToken {
        var characters: Int
        var whole: Int
        var fraction: String
    }

    private enum NumberShape {
        case groupedComma
        case groupedDot
        case decimalComma
        case decimalDot
    }

    private enum MoneyUnit {
        case euro
        case dollar
        case pound
    }

    private struct Hit {
        var characters: Int
        var replacement: String
    }

    private static func verbalizing(_ text: String, language: SpokenLanguage) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            // Copying the tail for every word is quadratic. Only a digit, a price
            // sign, or a version marker can start a quantity, so other words are copied as-is.
            if SpokenText.startsToken(text, at: index), looksQuantitative(text, at: index),
               let hit = match(String(text[index...]), language: language),
               hit.characters > 0 {
                result += hit.replacement
                index = text.index(index, offsetBy: hit.characters)
                continue
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private static func expandingUnits(_ text: String, language: SpokenLanguage) -> String {
        let celsius: String
        let fahrenheit: String
        switch language {
        case .english:
            celsius = " degrees Celsius"
            fahrenheit = " degrees Fahrenheit"
        case .french:
            celsius = " degrés Celsius"
            fahrenheit = " degrés Fahrenheit"
        }
        var text = text.replacingOccurrences(of: "°C", with: celsius)
        text = text.replacingOccurrences(of: "°F", with: fahrenheit)
        let pairs: [(String, String)]
        switch language {
        case .english:
            pairs = [("km", "kilometers"), ("kg", "kilograms")]
        case .french:
            pairs = [("km", "kilomètres"), ("kg", "kilogrammes")]
        }
        for (token, spoken) in pairs {
            text = SpokenText.rewrite(text, pattern: "(?i)\\b\(token)\\b") { _, _ in spoken }
        }
        return text
    }

    private static func looksQuantitative(_ text: String, at index: String.Index) -> Bool {
        let character = text[index]
        if character.isNumber || character == "€" || character == "$" || character == "£" { return true }
        guard character == "v" || character == "V" else { return false }
        let next = text.index(after: index)
        if next < text.endIndex, text[next].isNumber { return true }
        return text[index...].prefix(7).lowercased().hasPrefix("version")
    }

    private static func match(_ rest: String, language: SpokenLanguage) -> Hit? {
        if let hit = version(rest, language: language) { return hit }
        if let hit = currency(rest, language: language) { return hit }
        if let hit = percent(rest, language: language) { return hit }
        if let hit = date(rest, language: language) { return hit }
        if let hit = time(rest, language: language) { return hit }
        if let token = scanNumber(rest, language: language), followsBoundary(rest, after: token.characters) {
            return Hit(characters: token.characters, replacement: plain(token, language: language))
        }
        return nil
    }

    private static func followsBoundary(_ rest: String, after count: Int) -> Bool {
        let after = rest.dropFirst(count)
        guard let next = after.first else { return true }
        return !next.isLetter && !next.isNumber
    }

    private static func version(_ rest: String, language: SpokenLanguage) -> Hit? {
        if let groups = SpokenText.prefixMatch(#"(?i)^(version)\s+v?(\d+(?:\.\d+){1,3})(?![A-Za-z0-9])"#, in: rest),
           groups.count > 2 {
            let lead = groups[1].first?.isUppercase == true ? "Version" : "version"
            let spoken = versionParts(groups[2], language: language)
            return Hit(characters: groups[0].count, replacement: "\(lead) \(spoken)")
        }
        if let groups = SpokenText.prefixMatch(#"(?i)^v(\d+(?:\.\d+){1,3})(?![A-Za-z0-9])"#, in: rest),
           groups.count > 1 {
            let lead = groups[0].first?.isUppercase == true ? "Version" : "version"
            return Hit(characters: groups[0].count, replacement: "\(lead) \(versionParts(groups[1], language: language))")
        }
        return nil
    }

    private static func versionParts(_ dotted: String, language: SpokenLanguage) -> String {
        dotted.split(separator: ".").map { part in
            SpokenNumbers.words(Int(part) ?? 0, language: language)
        }.joined(separator: " point ")
    }

    private static func currency(_ rest: String, language: SpokenLanguage) -> Hit? {
        if let first = rest.first, let unit = unit(for: first) {
            var extra = 1
            var tail = rest.dropFirst()
            if tail.first == " " {
                extra += 1
                tail = tail.dropFirst()
            }
            if let token = scanNumber(String(tail), language: language),
               followsBoundary(String(tail), after: token.characters) {
                return Hit(
                    characters: extra + token.characters,
                    replacement: money(token, unit: unit, language: language)
                )
            }
        }
        if let token = scanNumber(rest, language: language) {
            let tail = rest.dropFirst(token.characters)
            var extra = 0
            var cursor = tail
            if cursor.first == " " {
                extra += 1
                cursor = cursor.dropFirst()
            }
            if let symbol = cursor.first, let unit = unit(for: symbol),
               followsBoundary(String(cursor), after: 1) {
                return Hit(
                    characters: token.characters + extra + 1,
                    replacement: money(token, unit: unit, language: language)
                )
            }
        }
        return nil
    }

    private static func unit(for symbol: Character) -> MoneyUnit? {
        switch symbol {
        case "€": .euro
        case "$": .dollar
        case "£": .pound
        default: nil
        }
    }

    private static func percent(_ rest: String, language: SpokenLanguage) -> Hit? {
        guard let token = scanNumber(rest, language: language) else { return nil }
        let tail = rest.dropFirst(token.characters)
        let spaced = tail.first == " "
        let mark = spaced ? tail.dropFirst().first : tail.first
        guard mark == "%" else { return nil }
        let consumed = token.characters + (spaced ? 2 : 1)
        guard followsBoundary(rest, after: consumed) else { return nil }
        return Hit(characters: consumed, replacement: percentWords(token, language: language))
    }

    private static func date(_ rest: String, language: SpokenLanguage) -> Hit? {
        if let groups = SpokenText.prefixMatch(#"^(\d{4})-(\d{2})-(\d{2})(?![0-9])"#, in: rest),
           groups.count > 3,
           let year = Int(groups[1]), let month = Int(groups[2]), let day = Int(groups[3]),
           valid(day: day, month: month, year: year) {
            return Hit(characters: groups[0].count, replacement: dateWords(day: day, month: month, year: year, language: language))
        }
        if let groups = SpokenText.prefixMatch(#"^(\d{1,2})/(\d{1,2})/(\d{4})(?![0-9])"#, in: rest),
           groups.count > 3,
           let first = Int(groups[1]), let second = Int(groups[2]), let year = Int(groups[3]),
           let parts = slashDate(first: first, second: second, year: year, language: language) {
            return Hit(
                characters: groups[0].count,
                replacement: dateWords(day: parts.day, month: parts.month, year: year, language: language)
            )
        }
        return nil
    }

    /// English slash dates are month/day. French slash dates are day/month. A number past 12
    /// forces the only order that can be a calendar date, in either language.
    private static func slashDate(first: Int, second: Int, year: Int, language: SpokenLanguage) -> (day: Int, month: Int)? {
        var day = first
        var month = second
        switch language {
        case .english:
            month = first
            day = second
        case .french:
            day = first
            month = second
        }
        if first > 12, second <= 12 {
            day = first
            month = second
        } else if second > 12, first <= 12 {
            month = first
            day = second
        }
        guard valid(day: day, month: month, year: year) else { return nil }
        return (day, month)
    }

    private static func valid(day: Int, month: Int, year: Int) -> Bool {
        guard (1...12).contains(month), (1_000...9_999).contains(year) else { return false }
        let lengths = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        var last = lengths[month]
        if month == 2, year % 4 == 0, (year % 100 != 0 || year % 400 == 0) { last = 29 }
        return (1...last).contains(day)
    }

    private static func time(_ rest: String, language: SpokenLanguage) -> Hit? {
        guard let groups = SpokenText.prefixMatch(
            #"^(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*([AaPp])\.?[Mm]\.?)?"#,
            in: rest
        ), groups.count > 2, let hour = Int(groups[1]), let minute = Int(groups[2]) else { return nil }
        guard followsBoundary(rest, after: groups[0].count) else { return nil }
        let second = groups.count > 3 && !groups[3].isEmpty ? Int(groups[3]) : nil
        let marker = groups.count > 4 && !groups[4].isEmpty ? groups[4] : nil
        guard let clock = clock(hour: hour, minute: minute, second: second, marker: marker, language: language) else {
            return nil
        }
        return Hit(characters: groups[0].count, replacement: clock)
    }

    /// `1,200` is one thousand two hundred in both languages: a comma followed by groups of three
    /// digits is a thousands separator. A comma followed by one or two digits is a French decimal.
    /// A dot is a decimal in English, and a thousands separator in French only when the groups
    /// are three digits (`1.200`).
    private static func scanNumber(_ rest: String, language: SpokenLanguage) -> NumberToken? {
        let patterns: [(String, NumberShape)]
        switch language {
        case .english:
            patterns = [
                (#"^\d{1,3}(?:,\d{3})+(?:\.\d+)?"#, .groupedComma),
                (#"^\d+(?:\.\d+)?"#, .decimalDot),
            ]
        case .french:
            patterns = [
                (#"^\d{1,3}(?:,\d{3})+(?:\.\d+)?"#, .groupedComma),
                (#"^\d{1,3}(?:\.\d{3})+(?:,\d+)?"#, .groupedDot),
                (#"^\d+,\d+"#, .decimalComma),
                (#"^\d+(?:\.\d+)?"#, .decimalDot),
            ]
        }
        var best: (String, NumberShape)?
        for (pattern, shape) in patterns {
            guard let groups = SpokenText.prefixMatch(pattern, in: rest) else { continue }
            let token = groups[0]
            if best == nil || token.count > best!.0.count {
                best = (token, shape)
            }
        }
        guard let best else { return nil }
        guard let value = interpret(best.0, shape: best.1) else { return nil }
        return NumberToken(characters: best.0.count, whole: value.whole, fraction: value.fraction)
    }

    private static func interpret(_ token: String, shape: NumberShape) -> (whole: Int, fraction: String)? {
        switch shape {
        case .groupedComma:
            return split(token, separator: ".", drop: ",")
        case .groupedDot:
            return split(token, separator: ",", drop: ".")
        case .decimalComma:
            return split(token, separator: ",", drop: "")
        case .decimalDot:
            return split(token, separator: ".", drop: "")
        }
    }

    private static func split(_ token: String, separator: Character, drop: String) -> (whole: Int, fraction: String)? {
        let pieces = token.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false)
        let wholeDigits = pieces[0].filter { !drop.contains($0) }
        guard wholeDigits.count <= 15, let whole = Int(wholeDigits), wholeDigits.allSatisfy(\.isNumber) else { return nil }
        let fraction = pieces.count > 1 ? String(pieces[1]) : ""
        guard fraction.allSatisfy(\.isNumber) else { return nil }
        return (whole, fraction)
    }

    private static func significant(_ fraction: String) -> String {
        var digits = fraction
        while digits.last == "0" { digits.removeLast() }
        return digits
    }

    private static func plain(_ token: NumberToken, language: SpokenLanguage) -> String {
        let fraction = significant(token.fraction)
        let whole = SpokenNumbers.words(token.whole, language: language)
        if fraction.isEmpty { return whole }
        let digits = SpokenNumbers.digitWords(fraction, language: language)
        switch language {
        case .english: return "\(whole) point \(digits)"
        case .french: return "\(whole) virgule \(digits)"
        }
    }

    private static func percentWords(_ token: NumberToken, language: SpokenLanguage) -> String {
        switch language {
        case .english:
            return "\(plain(token, language: language)) percent"
        case .french:
            if token.whole == 100, significant(token.fraction).isEmpty { return "cent pour cent" }
            return "\(plain(token, language: language)) pour cent"
        }
    }

    private static func cents(from fraction: String) -> Int {
        if fraction.isEmpty { return 0 }
        var digits = fraction
        if digits.count == 1 { digits.append("0") }
        return Int(digits.prefix(2)) ?? 0
    }

    private static func money(_ token: NumberToken, unit: MoneyUnit, language: SpokenLanguage) -> String {
        let minor = cents(from: token.fraction)
        if token.whole == 0, minor == 0 { return major(0, unit: unit, language: language) }
        if minor == 0 { return major(token.whole, unit: unit, language: language) }
        if token.whole == 0 { return minorWords(minor, unit: unit, language: language) }
        switch language {
        case .english:
            return "\(major(token.whole, unit: unit, language: language)) and \(minorWords(minor, unit: unit, language: language))"
        case .french:
            return "\(major(token.whole, unit: unit, language: language)) et \(minorWords(minor, unit: unit, language: language))"
        }
    }

    private static func major(_ count: Int, unit: MoneyUnit, language: SpokenLanguage) -> String {
        let name: String
        switch (unit, language, count == 1) {
        case (.euro, .english, true): name = "euro"
        case (.euro, .english, false): name = "euros"
        case (.euro, .french, true): name = "euro"
        case (.euro, .french, false): name = "euros"
        case (.dollar, .english, true): name = "dollar"
        case (.dollar, .english, false): name = "dollars"
        case (.dollar, .french, true): name = "dollar"
        case (.dollar, .french, false): name = "dollars"
        case (.pound, .english, true): name = "pound"
        case (.pound, .english, false): name = "pounds"
        case (.pound, .french, true): return "une livre"
        case (.pound, .french, false): name = "livres"
        }
        if language == .french, count == 1, unit == .euro { return "un euro" }
        if language == .french, count == 1, unit == .dollar { return "un dollar" }
        return "\(SpokenNumbers.words(count, language: language)) \(name)"
    }

    private static func minorWords(_ count: Int, unit: MoneyUnit, language: SpokenLanguage) -> String {
        let name: String
        switch (unit, language, count == 1) {
        case (.pound, .english, true): name = "penny"
        case (.pound, .english, false): name = "pence"
        case (.pound, .french, true): name = "penny"
        case (.pound, .french, false): name = "pence"
        case (.euro, .french, true): name = "centime"
        case (.euro, .french, false): name = "centimes"
        case (_, _, true): name = "cent"
        case (_, _, false): name = "cents"
        }
        if language == .french, count == 1, unit == .euro { return "un centime" }
        if language == .french, count == 1, unit != .pound { return "un cent" }
        return "\(SpokenNumbers.words(count, language: language)) \(name)"
    }

    private static let englishMonths = [
        "", "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    private static let frenchMonths = [
        "", "janvier", "février", "mars", "avril", "mai", "juin",
        "juillet", "août", "septembre", "octobre", "novembre", "décembre",
    ]

    private static let englishOrdinals = [
        "", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth",
        "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth",
        "seventeenth", "eighteenth", "nineteenth", "twentieth", "twenty-first", "twenty-second",
        "twenty-third", "twenty-fourth", "twenty-fifth", "twenty-sixth", "twenty-seventh",
        "twenty-eighth", "twenty-ninth", "thirtieth", "thirty-first",
    ]

    private static func dateWords(day: Int, month: Int, year: Int, language: SpokenLanguage) -> String {
        let yearWords = yearWords(year, language: language)
        switch language {
        case .english:
            return "\(englishMonths[month]) \(englishOrdinals[day]) \(yearWords)"
        case .french:
            return "\(SpokenNumbers.words(day, language: .french)) \(frenchMonths[month]) \(yearWords)"
        }
    }

    private static func yearWords(_ year: Int, language: SpokenLanguage) -> String {
        switch language {
        case .english:
            if year == 2000 { return "two thousand" }
            if (2001...2009).contains(year) {
                return "two thousand \(SpokenNumbers.words(year - 2000, language: .english))"
            }
            if (2010...2099).contains(year) {
                return "twenty \(SpokenNumbers.words(year - 2000, language: .english))"
            }
            if (1100...1999).contains(year) {
                let century = year / 100
                let rest = year % 100
                let head = SpokenNumbers.words(century, language: .english)
                if rest == 0 { return "\(head) hundred" }
                return "\(head) \(SpokenNumbers.words(rest, language: .english))"
            }
            return SpokenNumbers.words(year, language: .english)
        case .french:
            return SpokenNumbers.words(year, language: .french)
        }
    }

    private static func clock(hour: Int, minute: Int, second: Int?, marker: String?, language: SpokenLanguage) -> String? {
        guard (0...59).contains(minute), second == nil || (0...59).contains(second ?? 0) else { return nil }
        guard let hour = normalizedHour(hour, marker: marker) else { return nil }
        switch language {
        case .english:
            return englishClock(hour: hour, minute: minute, second: second)
        case .french:
            return frenchClock(hour: hour, minute: minute, second: second)
        }
    }

    private static func normalizedHour(_ hour: Int, marker: String?) -> Int? {
        guard let marker else { return (0...23).contains(hour) ? hour : nil }
        guard (1...12).contains(hour) else { return nil }
        switch marker.lowercased() {
        case "a": return hour == 12 ? 0 : hour
        case "p": return hour == 12 ? 12 : hour + 12
        default: return nil
        }
    }

    private static func englishClock(hour: Int, minute: Int, second: Int?) -> String {
        let shown: Int
        let suffix: String
        if hour == 0 {
            shown = 12
            suffix = " a m"
        } else if hour < 12 {
            shown = hour
            suffix = ""
        } else if hour == 12 {
            shown = 12
            suffix = ""
        } else {
            shown = hour - 12
            suffix = " p m"
        }
        let hourWords = SpokenNumbers.words(shown, language: .english)
        let body: String
        if minute == 0, second == nil || second == 0 {
            body = "\(hourWords) o'clock"
        } else if minute < 10 {
            body = "\(hourWords) oh \(SpokenNumbers.words(minute, language: .english))"
        } else {
            body = "\(hourWords) \(SpokenNumbers.words(minute, language: .english))"
        }
        var spoken = body + suffix
        if let second, second > 0 {
            let unit = second == 1 ? "second" : "seconds"
            spoken += " and \(SpokenNumbers.words(second, language: .english)) \(unit)"
        }
        return spoken
    }

    private static func frenchClock(hour: Int, minute: Int, second: Int?) -> String {
        let head: String
        if hour == 0 {
            head = "zéro heure"
        } else if hour == 1 {
            head = "une heure"
        } else {
            head = "\(SpokenNumbers.words(hour, language: .french)) heures"
        }
        var spoken = head
        if minute > 0 {
            spoken += " \(SpokenNumbers.words(minute, language: .french))"
        }
        if let second, second > 0 {
            let unit = second == 1 ? "seconde" : "secondes"
            spoken += " et \(SpokenNumbers.words(second, language: .french)) \(unit)"
        }
        return spoken
    }
}
