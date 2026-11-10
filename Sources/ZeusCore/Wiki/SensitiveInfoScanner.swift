import Foundation

/// One thing in a text that must not reach a global page unless the person says it may.
public struct SensitiveFinding: Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case email, phone, address, card, iban, secret, health, finance, personName

        public var label: String {
            switch self {
            case .email: return "Email address"
            case .phone: return "Phone number"
            case .address: return "Street address"
            case .card: return "Card number"
            case .iban: return "Bank account (IBAN)"
            case .secret: return "Key or token"
            case .health: return "Health term"
            case .finance: return "Finance term"
            case .personName: return "Person's name"
            }
        }
    }

    public var kind: Kind
    /// UTF-16 offsets into the scanned string (the `NSString` view).
    public var range: Range<Int>
    public var matched: String

    public init(kind: Kind, range: Range<Int>, matched: String) {
        self.kind = kind
        self.range = range
        self.matched = matched
    }

    public var id: String { "\(kind.rawValue)@\(range.lowerBound)-\(range.upperBound)" }

    /// What a person acknowledges. Position-independent, so the same item appearing twice is one decision.
    public var acknowledgementKey: String {
        "\(kind.rawValue)|\(matched.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))"
    }

    /// Safe to show or speak: card numbers, bank accounts and keys keep only their first and last two characters.
    public var redacted: String {
        switch kind {
        case .card, .iban, .secret:
            guard matched.count > 8 else { return "…" }
            return String(matched.prefix(2)) + "…" + String(matched.suffix(2))
        default:
            return matched
        }
    }

    public func swiftRange(in text: String) -> Range<String.Index>? {
        Range(NSRange(location: range.lowerBound, length: range.count), in: text)
    }
}

public enum SensitiveInfoScanner {
    /// Findings sorted by position. `participantNames` are the people of the meetings behind the text: a full
    /// name and each name part of three or more letters count (whole words, any case).
    public static func scan(_ text: String, participantNames: [String] = []) -> [SensitiveFinding] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        var found: [SensitiveFinding] = []

        func add(_ kind: SensitiveFinding.Kind, _ range: NSRange) {
            found.append(SensitiveFinding(
                kind: kind,
                range: range.location..<(range.location + range.length),
                matched: ns.substring(with: range)
            ))
        }

        for range in matches(email, in: ns) { add(.email, range) }

        var cardRanges: [NSRange] = []
        for range in matches(card, in: ns) {
            let digits = digitsOf(ns.substring(with: range))
            if (13...19).contains(digits.count), isLuhnValid(digits) {
                cardRanges.append(range)
                add(.card, range)
            }
        }

        for range in matches(phone, in: ns) where isPhone(ns.substring(with: range)) {
            if cardRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) { continue }
            add(.phone, range)
        }

        for range in matches(ibanCandidate, in: ns) {
            if let trimmed = validIBANRange(ns.substring(with: range), at: range.location) { add(.iban, trimmed) }
        }

        for expression in secretPatterns {
            for range in matches(expression, in: ns) { add(.secret, range) }
        }
        for range in matches(base64Candidate, in: ns) where looksLikeBase64Secret(ns.substring(with: range)) {
            add(.secret, range)
        }

        for range in matches(address, in: ns) { add(.address, range) }
        for range in matches(postBox, in: ns) { add(.address, range) }
        for range in matches(healthWords, in: ns) { add(.health, range) }
        for range in matches(financeWords, in: ns) { add(.finance, range) }

        for expression in nameExpressions(participantNames) {
            for range in matches(expression, in: ns) { add(.personName, range) }
        }

        found.sort { ($0.range.lowerBound, $0.range.upperBound, $0.kind.rawValue) < ($1.range.lowerBound, $1.range.upperBound, $1.kind.rawValue) }
        return removingContained(found)
    }

    // MARK: Checks

    /// Luhn checksum over a string of ASCII digits.
    public static func isLuhnValid(_ digits: String) -> Bool {
        let values = digits.unicodeScalars.compactMap { scalar -> Int? in
            (48...57).contains(scalar.value) ? Int(scalar.value) - 48 : nil
        }
        guard values.count == digits.unicodeScalars.count, values.count >= 2 else { return false }
        var sum = 0
        for (position, digit) in values.reversed().enumerated() {
            var value = digit
            if position % 2 == 1 {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
        }
        return sum % 10 == 0
    }

    /// ISO 13616 mod-97 check over an IBAN without spaces.
    public static func isIBANValid(_ compact: String) -> Bool {
        let value = compact.uppercased()
        guard (15...34).contains(value.count), value.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }
        let chars = Array(value)
        guard chars[0].isLetter, chars[1].isLetter, chars[2].isNumber, chars[3].isNumber else { return false }
        var remainder = 0
        for character in chars.dropFirst(4) + chars.prefix(4) {
            guard let scalar = character.unicodeScalars.first else { return false }
            let code = Int(scalar.value)
            if (48...57).contains(code) {
                remainder = (remainder * 10 + (code - 48)) % 97
            } else if (65...90).contains(code) {
                remainder = (remainder * 100 + (code - 55)) % 97
            } else {
                return false
            }
        }
        return remainder == 1
    }

    // MARK: Patterns (built per use: NSRegularExpression is not Sendable-annotated everywhere)

    private static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        } catch {
            preconditionFailure("Invalid sensitive-info pattern \(pattern): \(error)")
        }
    }

    private static func matches(_ expression: NSRegularExpression, in ns: NSString) -> [NSRange] {
        expression
            .matches(in: ns as String, options: [], range: NSRange(location: 0, length: ns.length))
            .map(\.range)
    }

    private static var email: NSRegularExpression {
        regex(#"[A-Z0-9._%+\-]+@[A-Z0-9\-]+(?:\.[A-Z0-9\-]+)*\.[A-Z]{2,}"#, caseInsensitive: true)
    }

    /// Whole-number candidates only (contiguous, grouped 4-4-4-4, or 4-6-5); Luhn decides.
    private static var card: NSRegularExpression {
        regex(#"(?<!\d)(?:\d{13,19}|\d{4}(?:[ \-]\d{4}){2,3}(?:[ \-]\d{1,3})?|\d{4}[ \-]\d{6}[ \-]\d{5})(?!\d)"#)
    }

    private static var phone: NSRegularExpression {
        regex(#"(?<!\w)\+?\(?\d[\d \t.()\-]{7,}\d"#)
    }

    private static var ibanCandidate: NSRegularExpression {
        regex(#"(?<![A-Za-z0-9])[A-Za-z]{2}\d{2}(?: ?[A-Za-z0-9]{1,4}){3,8}(?![A-Za-z0-9])"#)
    }

    private static var secretPatterns: [NSRegularExpression] {
        [
            regex(#"\bsk-[A-Za-z0-9_\-]{16,}"#),
            regex(#"\bgh[pousr]_[A-Za-z0-9]{20,}"#),
            regex(#"\bxox[abeprs]-[A-Za-z0-9\-]{10,}"#),
            regex(#"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#),
            regex(#"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{4,}"#),
            regex(#"-----BEGIN [A-Z ]*PRIVATE KEY-----"#),
            regex(#"\b[0-9a-fA-F]{32,}\b"#),
            regex(#"\bbearer\s+[A-Za-z0-9._\-]{20,}"#, caseInsensitive: true),
        ]
    }

    private static var base64Candidate: NSRegularExpression {
        regex(#"(?<![A-Za-z0-9+/=_\-])[A-Za-z0-9+/_\-]{40,}={0,2}(?![A-Za-z0-9+/=_\-])"#)
    }

    private static var address: NSRegularExpression {
        regex(
            #"\b\d{1,6}[ \t]+(?:[A-Za-z0-9.'\-]+[ \t]+){1,4}?(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Way|Place|Pl|Terrace|Highway|Hwy)\b\.?"#,
            caseInsensitive: true
        )
    }

    private static var postBox: NSRegularExpression {
        regex(#"\bP\.?[ \t]?O\.?[ \t]?Box[ \t]+\d+"#, caseInsensitive: true)
    }

    private static let healthTerms = [
        "diagnosis", "diagnosed", "medication", "prescription", "prescribed", "therapy", "therapist", "surgery",
        "cancer", "diabetes", "diabetic", "hiv", "pregnant", "pregnancy", "medical condition", "medical record",
        "patient", "symptoms", "mental health", "depression", "anxiety", "blood pressure", "chemotherapy", "disability",
    ]

    private static let financeTerms = [
        "salary", "payroll", "bank account", "account number", "routing number", "sort code", "mortgage", "loan",
        "debt", "tax return", "credit card", "debit card", "net worth", "bankruptcy", "credit score", "social security",
    ]

    private static var healthWords: NSRegularExpression { wordList(healthTerms) }
    private static var financeWords: NSRegularExpression { wordList(financeTerms) }

    private static func wordList(_ terms: [String]) -> NSRegularExpression {
        let alternatives = terms.map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: #"\s+"#) }
        return regex(#"\b(?:"# + alternatives.joined(separator: "|") + #")\b"#, caseInsensitive: true)
    }

    private static func nameExpressions(_ names: [String]) -> [NSRegularExpression] {
        let generic: Set<String> = ["speaker", "you", "unknown", "participant", "me"]
        var seen = Set<String>()
        var expressions: [NSRegularExpression] = []
        func addWord(_ pattern: String) {
            if seen.insert(pattern.lowercased()).inserted {
                expressions.append(regex(#"\b"# + pattern + #"\b"#, caseInsensitive: true))
            }
        }
        for name in names {
            let parts = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard !parts.isEmpty, !generic.contains(parts.joined(separator: " ").lowercased()) else { continue }
            if parts.count > 1 {
                addWord(parts.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: #"\s+"#))
            }
            for part in parts where part.count >= 3 && !generic.contains(part.lowercased()) {
                addWord(NSRegularExpression.escapedPattern(for: part))
            }
        }
        return expressions
    }

    // MARK: Helpers

    private static func digitsOf(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { (48...57).contains($0.value) }))
    }

    private static func isPhone(_ candidate: String) -> Bool {
        let digitCount = digitsOf(candidate).count
        let hasPlus = candidate.hasPrefix("+")
        let inRange = (10...15).contains(digitCount) || (hasPlus && (8...15).contains(digitCount))
        guard inRange else { return false }
        // A date and a decimal number are not phone numbers.
        if candidate.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil { return false }
        let separators = candidate.filter { !$0.isNumber }
        if separators.count == 1, separators.first == "." { return false }
        return true
    }

    /// The longest prefix of the candidate (spaces ignored) that is a valid IBAN, as a range in the full text.
    private static func validIBANRange(_ candidate: String, at location: Int) -> NSRange? {
        let units = Array(candidate.utf16)
        var positions: [Int] = []
        for (offset, unit) in units.enumerated() where unit != 32 { positions.append(offset) }
        guard positions.count >= 15 else { return nil }
        let characters = positions.map { Character(UnicodeScalar(units[$0]) ?? " ") }
        for length in stride(from: min(34, positions.count), through: 15, by: -1) {
            if isIBANValid(String(characters.prefix(length))) {
                let end = positions[length - 1] + 1
                return NSRange(location: location, length: end)
            }
        }
        return nil
    }

    /// Long, mixed-case, with a digit, and not shaped like a path or a hyphenated slug.
    private static func looksLikeBase64Secret(_ candidate: String) -> Bool {
        guard candidate.contains(where: { $0.isNumber }),
              candidate.contains(where: { $0.isUppercase }),
              candidate.contains(where: { $0.isLowercase }) else { return false }
        let separators = candidate.filter { $0 == "/" || $0 == "-" }.count
        return separators <= 3 && !candidate.contains("//")
    }

    /// Drops a finding that sits inside another of the same kind (and exact duplicates).
    private static func removingContained(_ findings: [SensitiveFinding]) -> [SensitiveFinding] {
        var kept: [SensitiveFinding] = []
        for (index, item) in findings.enumerated() {
            var contained = false
            for (otherIndex, other) in findings.enumerated() where otherIndex != index && other.kind == item.kind {
                let covers = other.range.lowerBound <= item.range.lowerBound && other.range.upperBound >= item.range.upperBound
                if covers && (other.range != item.range || otherIndex < index) {
                    contained = true
                    break
                }
            }
            if !contained { kept.append(item) }
        }
        return kept
    }
}

// MARK: - Promotion

public enum WikiPromotionError: LocalizedError, Equatable {
    case missingPromoter
    /// The findings still unacknowledged.
    case blocked([SensitiveFinding])
    /// The page may still hold text from a forgotten source. The person must review it first.
    case needsReview

    public var errorDescription: String? {
        switch self {
        case .needsReview:
            return "This page needs your review before it can go global. Read it, then choose “I've reviewed this”."
        case .missingPromoter:
            return "Promotion needs to record who promoted the page, and no user name was given."
        case .blocked(let findings):
            return "\(findings.count) sensitive item(s) must be removed or acknowledged before this page can go global."
        }
    }
}

/// The only way a page becomes `.global`.
public enum WikiPromotion {
    /// The exact text that is scanned (title, then body). Finding ranges are offsets into this string.
    public static func scannedText(_ page: WikiPage) -> String {
        page.title + "\n\n" + page.body
    }

    public static func findings(for page: WikiPage) -> [SensitiveFinding] {
        SensitiveInfoScanner.scan(scannedText(page), participantNames: page.participantNames)
    }

    /// Runs the scanner and promotes only when every finding's `acknowledgementKey` is in `acknowledged`.
    /// Records who promoted it and when. Throws without changing anything otherwise.
    public static func promote(_ page: WikiPage, promotedBy: String, acknowledged: Set<String>, now: Date) throws -> WikiPage {
        let promoter = promotedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promoter.isEmpty else { throw WikiPromotionError.missingPromoter }
        guard !page.needsReview else { throw WikiPromotionError.needsReview }
        let unresolved = findings(for: page).filter { !acknowledged.contains($0.acknowledgementKey) }
        guard unresolved.isEmpty else { throw WikiPromotionError.blocked(unresolved) }
        var promoted = page
        promoted.scope = .global
        promoted.promotedBy = promoter
        promoted.promotedAt = now
        return promoted
    }

    /// Back to personal. Always allowed.
    public static func demote(_ page: WikiPage) -> WikiPage {
        var personal = page
        personal.scope = .personal
        personal.promotedBy = nil
        personal.promotedAt = nil
        return personal
    }
}
