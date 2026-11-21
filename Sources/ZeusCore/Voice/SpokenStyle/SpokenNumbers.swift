import Foundation

/// Cardinal numbers for speech. French keeps the plural on "cent" and "vingt" only when that
/// word ends the number, which is what `terminal` tracks.
enum SpokenNumbers {
    static func words(_ value: Int, language: SpokenLanguage) -> String {
        switch language {
        case .english:
            return english(value)
        case .french:
            return french(value, terminal: true)
        }
    }

    static func digitWords(_ digits: String, language: SpokenLanguage) -> String {
        digits.map { character in
            words(Int(String(character)) ?? 0, language: language)
        }.joined(separator: " ")
    }

    private static let englishUnder20 = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen",
    ]

    private static let englishTens = [
        "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
    ]

    private static func english(_ value: Int) -> String {
        if value == 0 { return "zero" }
        if value < 0 { return "minus " + english(-value) }
        var remaining = value
        var parts: [String] = []
        let scales = [(1_000_000_000, "billion"), (1_000_000, "million"), (1_000, "thousand")]
        for (scale, name) in scales where remaining >= scale {
            let count = remaining / scale
            remaining %= scale
            parts.append("\(english(count)) \(name)")
        }
        if remaining > 0 {
            if remaining < 100, !parts.isEmpty {
                parts.append("and \(englishUnder100(remaining))")
            } else {
                parts.append(englishUnder1000(remaining))
            }
        }
        return parts.joined(separator: " ")
    }

    private static func englishUnder1000(_ value: Int) -> String {
        if value < 100 { return englishUnder100(value) }
        let hundreds = value / 100
        let rest = value % 100
        let head = "\(englishUnder20[hundreds]) hundred"
        if rest == 0 { return head }
        return "\(head) and \(englishUnder100(rest))"
    }

    private static func englishUnder100(_ value: Int) -> String {
        if value < 20 { return englishUnder20[value] }
        let ten = value / 10
        let unit = value % 10
        if unit == 0 { return englishTens[ten] }
        return "\(englishTens[ten])-\(englishUnder20[unit])"
    }

    private static let frenchUnits = [
        "zéro", "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf",
        "dix", "onze", "douze", "treize", "quatorze", "quinze", "seize",
    ]

    private static func french(_ value: Int, terminal: Bool) -> String {
        if value == 0 { return "zéro" }
        if value < 0 { return "moins " + french(-value, terminal: true) }
        if value < 100 { return frenchUnder100(value, terminal: terminal) }
        if value < 1_000 { return frenchUnder1000(value, terminal: terminal) }
        if value >= 1_000_000_000 {
            return frenchScale(value, scale: 1_000_000_000, one: "un milliard", many: "milliards", terminal: terminal)
        }
        if value >= 1_000_000 {
            return frenchScale(value, scale: 1_000_000, one: "un million", many: "millions", terminal: terminal)
        }
        let count = value / 1_000
        let rest = value % 1_000
        let head = count == 1 ? "mille" : french(count, terminal: false) + " mille"
        if rest == 0 { return head }
        return head + " " + french(rest, terminal: terminal)
    }

    private static func frenchScale(
        _ value: Int,
        scale: Int,
        one: String,
        many: String,
        terminal: Bool
    ) -> String {
        let count = value / scale
        let rest = value % scale
        let head = count == 1 ? one : french(count, terminal: false) + " " + many
        if rest == 0 { return head }
        return head + " " + french(rest, terminal: terminal)
    }

    private static func frenchUnder1000(_ value: Int, terminal: Bool) -> String {
        let hundreds = value / 100
        let rest = value % 100
        let hundred: String
        if hundreds == 1 {
            hundred = "cent"
        } else {
            let plural = rest == 0 && terminal
            hundred = frenchUnder100(hundreds, terminal: true) + (plural ? " cents" : " cent")
        }
        if rest == 0 { return hundred }
        return hundred + " " + frenchUnder100(rest, terminal: terminal)
    }

    private static func frenchUnder100(_ value: Int, terminal: Bool) -> String {
        if value < 17 { return frenchUnits[value] }
        if value < 20 { return "dix-" + frenchUnits[value - 10] }
        if value < 70 {
            let names = ["", "", "vingt", "trente", "quarante", "cinquante", "soixante"]
            let ten = names[value / 10]
            let unit = value % 10
            if unit == 0 { return ten }
            if unit == 1 { return ten + "-et-un" }
            return ten + "-" + frenchUnits[unit]
        }
        if value < 80 {
            let rest = value - 60
            if rest == 11 { return "soixante-et-onze" }
            return "soixante-" + frenchUnder100(rest, terminal: true)
        }
        let rest = value - 80
        if rest == 0 { return terminal ? "quatre-vingts" : "quatre-vingt" }
        return "quatre-vingt-" + frenchUnder100(rest, terminal: true)
    }
}
