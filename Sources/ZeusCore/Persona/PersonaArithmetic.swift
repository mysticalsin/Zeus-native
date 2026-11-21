import Foundation

enum PersonaArithmetic {
    /// "what is 17 times 23" and "18% of 240", answered locally.
    static func answer(for transcript: String) -> String? {
        if let percent = percentage(for: transcript) { return percent }
        let key = Utterance(transcript).words.joined(separator: " ")
        guard key.contains("what is") || key.contains("what's") else { return nil }
        let ops: [(String, (Int, Int) -> Int)] = [
            ("times", *), ("multiplied by", *), ("plus", +), ("minus", -),
        ]
        for (word, op) in ops {
            guard key.contains(word) else { continue }
            let parts = key.split(separator: " ").map(String.init)
            guard let left = parts.compactMap({ Int($0) }).first,
                  let right = parts.compactMap({ Int($0) }).last,
                  left != right || parts.filter({ Int($0) != nil }).count >= 2 else { continue }
            return "\(op(left, right))."
        }
        return nil
    }

    /// "18% of 240" and "18 percent of 240", with an optional "what is".
    private static func percentage(for transcript: String) -> String? {
        let words = Utterance(transcript).words
        guard let ofIndex = words.firstIndex(of: "of"), ofIndex > 0, ofIndex + 1 < words.count else { return nil }
        guard let base = decimal(words[ofIndex + 1]) else { return nil }
        let rate: Decimal
        let leadEnd: Int
        let rateWord = words[ofIndex - 1]
        if rateWord == "percent" || rateWord == "pct" {
            guard ofIndex >= 2, let value = decimal(words[ofIndex - 2]) else { return nil }
            rate = value
            leadEnd = ofIndex - 2
        } else if let value = percentToken(rateWord) {
            rate = value
            leadEnd = ofIndex - 1
        } else {
            return nil
        }
        let allowed: Set<String> = ["what", "is", "calculate", "compute", "how", "much"]
        guard words.prefix(leadEnd).allSatisfy(allowed.contains) else { return nil }
        let rest = words.suffix(from: words.index(after: ofIndex)).dropFirst()
        guard rest.isEmpty else { return nil }
        return spoken(rate * base / 100)
    }

    private static func percentToken(_ word: String) -> Decimal? {
        guard word.hasSuffix("%") else { return nil }
        return decimal(String(word.dropLast()))
    }

    private static func decimal(_ word: String) -> Decimal? {
        guard !word.isEmpty, word.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Decimal(string: word, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func spoken(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        let text = formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
        return text + "."
    }
}
