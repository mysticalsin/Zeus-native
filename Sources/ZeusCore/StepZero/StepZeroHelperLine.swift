import Foundation

/// One line of the step-zero helper. A line is at most 256 bytes, made of digits and closed words.
/// Anything else is refused. The helper prints yes or no for a comparison it holds in memory, and it does not print the text it compared.
public enum StepZeroHelperLine: Sendable, Equatable {
    public static let byteLimit = 256
    /// A count the report can store. A wider count is refused.
    public static let countLimit = 1_000_000

    /// Commands the helper reads.
    case read
    case cmd(Int)
    case seek
    case token(String)
    case poll(Int)

    /// What the helper prints. Yes and no are the comparison. The other cases name the fact.
    case yes
    case no
    /// The line `none`. The case is not named `none`, because that is `Optional.none` on a failable decode.
    case nothing
    case missing(Int)
    case cpu(Int)
    case elapsed(Int)
    case rate(Int)
    case playing(Bool)
    case title(Bool)
    case same(Bool)
    case notify(Bool)
    case seen(Bool)
    case appClass(AppClass)
    case art(Art)
    case gate(Gate)
    case bundleCall(BundleCall)
    case field(Field)

    /// The elected app's class, from the closed table.
    public enum AppClass: String, Sendable, Equatable, CaseIterable {
        case player
        case browser
        case video
        case call
        case other
    }

    /// Artwork bytes named from the closed list. The bytes themselves are not on the line.
    public enum Art: String, Sendable, Equatable, CaseIterable {
        case jpeg
        case png
        case other
    }

    /// Whether an ordinary process saw an item.
    public enum Gate: String, Sendable, Equatable, CaseIterable {
        case present
        case absent
        case unknown
    }

    /// Which bundle-id call answered, tried client then pid.
    public enum BundleCall: String, Sendable, Equatable, CaseIterable {
        case client
        case pid
        case none
        case unknown
    }

    /// A key that was present. The value is not on the line.
    public enum Field: String, Sendable, Equatable, CaseIterable {
        case app
        case parent
        case title
        case artist
        case album
        case duration
        case elapsed
        case rate
        case playing
        case key
    }

    /// The command numbers the probe sends: play, pause, next, and previous.
    public static let commandNumbers: Set<Int> = [0, 1, 4, 5]

    public static func decode(_ line: String) -> StepZeroHelperLine? {
        guard line.utf8.count <= byteLimit, !line.isEmpty, isClosedAlphabet(line) else { return nil }
        let parts = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, !parts.contains("") else { return nil }
        switch parts.count {
        case 1:
            return decodeOne(parts[0])
        case 2:
            return decodeTwo(parts[0], parts[1])
        default:
            return nil
        }
    }

    private static func isClosedAlphabet(_ line: String) -> Bool {
        for byte in line.utf8 {
            let digit = byte >= 48 && byte <= 57
            let letter = byte >= 97 && byte <= 122
            if !digit && !letter && byte != 32 { return false }
        }
        return true
    }

    private static func decodeOne(_ word: String) -> StepZeroHelperLine? {
        switch word {
        case "read": return .read
        case "seek": return .seek
        case "yes": return .yes
        case "no": return .no
        case "none": return .nothing
        default: return nil
        }
    }

    private static func decodeTwo(_ word: String, _ value: String) -> StepZeroHelperLine? {
        switch word {
        case "cmd":
            guard let number = count(value), commandNumbers.contains(number) else { return nil }
            return .cmd(number)
        case "token":
            guard isHex(value) else { return nil }
            return .token(value)
        case "poll":
            guard let seconds = count(value) else { return nil }
            return .poll(seconds)
        case "missing":
            guard let number = count(value) else { return nil }
            return .missing(number)
        case "cpu":
            guard let number = count(value) else { return nil }
            return .cpu(number)
        case "elapsed":
            guard let number = count(value) else { return nil }
            return .elapsed(number)
        case "rate":
            guard let number = count(value) else { return nil }
            return .rate(number)
        case "playing":
            guard let flag = yesNo(value) else { return nil }
            return .playing(flag)
        case "title":
            guard let flag = yesNo(value) else { return nil }
            return .title(flag)
        case "same":
            guard let flag = yesNo(value) else { return nil }
            return .same(flag)
        case "notify":
            guard let flag = yesNo(value) else { return nil }
            return .notify(flag)
        case "seen":
            guard let flag = yesNo(value) else { return nil }
            return .seen(flag)
        case "class":
            guard let kind = AppClass(rawValue: value) else { return nil }
            return .appClass(kind)
        case "art":
            guard let kind = Art(rawValue: value) else { return nil }
            return .art(kind)
        case "gate":
            guard let kind = Gate(rawValue: value) else { return nil }
            return .gate(kind)
        case "call":
            guard let kind = BundleCall(rawValue: value) else { return nil }
            return .bundleCall(kind)
        case "field":
            guard let kind = Field(rawValue: value) else { return nil }
            return .field(kind)
        default:
            return nil
        }
    }

    private static func yesNo(_ value: String) -> Bool? {
        switch value {
        case "yes": return true
        case "no": return false
        default: return nil
        }
    }

    /// ASCII digits, no leading zero except the number 0, and at most `countLimit`.
    private static func count(_ value: String) -> Int? {
        guard !value.isEmpty, value.count <= 7 else { return nil }
        if value.count > 1, value.first == "0" { return nil }
        guard value.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        guard let number = Int(value), number <= countLimit else { return nil }
        return number
    }

    /// Lowercase hex. The line's own byte limit is what stops a long token.
    private static func isHex(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.allSatisfy { ($0 >= "0" && $0 <= "9") || ($0 >= "a" && $0 <= "f") }
    }
}
