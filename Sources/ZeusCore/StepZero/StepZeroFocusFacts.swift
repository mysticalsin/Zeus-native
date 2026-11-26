import Foundation

/// The step-zero focus facts. Pure: it opens no store, starts no watch,
/// and keeps no name.
///
/// The caller feeds the two store files as bytes. Three fields of a live
/// record become yes or no, and the characters are dropped. A history list
/// is not read. The reader file, the section, and the focus lint stay out
/// of this file.
public enum StepZeroFocusFacts {
    /// One store file. Larger input is refused before a parse.
    public static let maxBytes = 4 * 1024 * 1024
    /// Live records past this count are not read.
    public static let maxRecords = 64
    /// Configuration entries past this count are not read.
    public static let maxModes = 64
    /// A mode id longer than this is not a read.
    public static let maxIdentifierCharacters = 200

    /// The list wrapper. A file with no such list is refused whole.
    public static let dataKey = "data"
    /// The only list this reader walks. Every other list is skipped.
    public static let liveRecordsKey = "storeAssertionRecords"
    public static let detailsKey = "assertionDetails"
    public static let identifierKey = "assertionDetailsModeIdentifier"
    public static let configurationsKey = "modeConfigurations"
    public static let modeKey = "mode"
    public static let nameKey = "name"
    public static let symbolKey = "symbolImageName"

    /// Presence only. A name, a symbol, and a mode id have no field here.
    public struct Fact: Sendable, Equatable {
        public var hasModeId: Bool
        public var idIsConfigKey: Bool
        public var hasName: Bool
        public var hasSymbol: Bool

        public init(hasModeId: Bool, idIsConfigKey: Bool, hasName: Bool, hasSymbol: Bool) {
            self.hasModeId = hasModeId
            self.idIsConfigKey = idIsConfigKey
            self.hasName = hasName
            self.hasSymbol = hasSymbol
        }
    }

    public enum Read: Sendable, Equatable {
        case live([Fact])
        case off
        case tooLarge
        case malformed
    }

    /// Reads at most `maxRecords` live elements and `maxModes` configuration
    /// keys. A record past the cap does not change a flag. A configuration
    /// past `maxBytes` is not parsed, and every configuration flag stays no.
    /// Assertions past `maxBytes` return `tooLarge` and nothing is parsed.
    public static func read(assertions: Data, configurations: Data?) -> Read {
        if assertions.count > maxBytes { return .tooLarge }
        guard let root = jsonObject(assertions) else { return .malformed }
        guard let entries = array(root[dataKey]) else { return .malformed }
        switch liveRecords(in: entries) {
        case .missing:
            return .off
        case .wrongType:
            return .malformed
        case .records(let records):
            if records.isEmpty { return .off }
            let modes = modeTable(configurations)
            var facts: [Fact] = []
            var walked = 0
            for record in records {
                if walked == maxRecords { break }
                walked += 1
                guard let row = dictionary(record) else { continue }
                facts.append(fact(row, modes))
            }
            if facts.isEmpty { return .off }
            return .live(facts)
        }
    }

    private enum LiveList {
        case missing
        case wrongType
        case records([Any])
    }

    private struct ModeBits {
        var hasName: Bool
        var hasSymbol: Bool
    }

    private static func liveRecords(in entries: [Any]) -> LiveList {
        for entry in entries {
            guard let object = dictionary(entry) else { continue }
            guard let raw = object[liveRecordsKey] else { continue }
            if raw is NSNull { return .records([]) }
            guard let records = array(raw) else { return .wrongType }
            return .records(records)
        }
        return .missing
    }

    /// Keys are examined in ascending order. A key past `maxModes` is not a
    /// configuration key, so its name and symbol stay no.
    private static func modeTable(_ configurations: Data?) -> [String: ModeBits] {
        guard let configurations, configurations.count <= maxBytes else { return [:] }
        guard let root = jsonObject(configurations) else { return [:] }
        guard let entries = array(root[dataKey]), let first = entries.first else { return [:] }
        guard let object = dictionary(first), let raw = dictionary(object[configurationsKey]) else { return [:] }
        var table: [String: ModeBits] = [:]
        for key in raw.keys.sorted().prefix(maxModes) {
            table[key] = bits(raw[key])
        }
        return table
    }

    private static func bits(_ value: Any?) -> ModeBits {
        guard let object = dictionary(value), let mode = dictionary(object[modeKey]) else {
            return ModeBits(hasName: false, hasSymbol: false)
        }
        return ModeBits(hasName: presentName(mode[nameKey]), hasSymbol: presentSymbol(mode[symbolKey]))
    }

    private static func fact(_ row: [String: Any], _ modes: [String: ModeBits]) -> Fact {
        guard let identifier = usableIdentifier(row) else {
            return Fact(hasModeId: false, idIsConfigKey: false, hasName: false, hasSymbol: false)
        }
        let matched = modes[identifier]
        return Fact(
            hasModeId: true,
            idIsConfigKey: matched != nil,
            hasName: matched?.hasName ?? false,
            hasSymbol: matched?.hasSymbol ?? false
        )
    }

    /// The nested id only. A flat key, a number, an empty string, a string of
    /// spaces, or a string past 200 characters is not a read. The characters
    /// are not returned.
    private static func usableIdentifier(_ row: [String: Any]) -> String? {
        guard let details = dictionary(row[detailsKey]) else { return nil }
        guard let text = string(details[identifierKey]) else { return nil }
        guard text.count >= 1, text.count <= maxIdentifierCharacters else { return nil }
        guard text.unicodeScalars.contains(where: { !isSpace($0) }) else { return nil }
        return text
    }

    private static func presentName(_ value: Any?) -> Bool {
        guard let text = string(value) else { return false }
        return text.unicodeScalars.contains(where: { !isSpace($0) })
    }

    /// One to 64 characters: lower-case letters, digits, and full stops.
    private static func presentSymbol(_ value: Any?) -> Bool {
        guard let text = string(value) else { return false }
        let scalars = Array(text.unicodeScalars)
        guard (1...64).contains(scalars.count) else { return false }
        return scalars.allSatisfy(isSymbol)
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let text = value as? NSString { return text as String }
        return nil
    }

    private static func isSymbol(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "0"..."9", ".":
            return true
        default:
            return false
        }
    }

    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case " ", "\t", "\n", "\r":
            return true
        default:
            return false
        }
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return dictionary(raw)
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        guard let value else { return nil }
        if let object = value as? [String: Any] { return object }
        guard let object = value as? NSDictionary else { return nil }
        var copy: [String: Any] = [:]
        copy.reserveCapacity(object.count)
        for (key, item) in object {
            guard let key = key as? String else { return nil }
            copy[key] = item
        }
        return copy
    }

    private static func array(_ value: Any?) -> [Any]? {
        guard let value, (value is NSNull) == false else { return nil }
        if let list = value as? [Any] { return list }
        guard let list = value as? NSArray else { return nil }
        return list.map { $0 }
    }
}
