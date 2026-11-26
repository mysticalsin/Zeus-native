import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// Cleans one Focus name or one symbol name. The store is the only caller.
/// Nothing here reads a file or asks for a permission.
public enum SystemFocusText {
    /// Drops controls, line breaks, bidirectional overrides and zero-width marks.
    /// A joiner stays only when it sits between two emoji. Spaces fold to one,
    /// ends are trimmed, and the result is at most 64 grapheme clusters.
    /// Empty is nil.
    public static func cleanName(_ raw: String) -> String? {
        var kept: [Unicode.Scalar] = []
        kept.reserveCapacity(raw.unicodeScalars.count)
        let scalars = Array(raw.unicodeScalars)
        for index in scalars.indices {
            let scalar = scalars[index]
            if scalar == joiner {
                let previous = kept.last
                let next = index + 1 < scalars.count ? scalars[index + 1] : nil
                if let previous, let next, isEmoji(previous), isEmoji(next) {
                    kept.append(scalar)
                }
                continue
            }
            if dropped(scalar) { continue }
            kept.append(scalar)
        }

        var folded: [Unicode.Scalar] = []
        folded.reserveCapacity(kept.count)
        var space = false
        for scalar in kept {
            if scalar.properties.isWhitespace {
                if !folded.isEmpty { space = true }
                continue
            }
            if space {
                folded.append(" ")
                space = false
            }
            folded.append(scalar)
        }
        let text = String(String.UnicodeScalarView(folded))
        guard !text.isEmpty else { return nil }
        return String(text.prefix(64))
    }

    /// One to 64 characters, lower-case letters, digits and full stops only.
    /// Anything else is nil.
    public static func cleanSymbol(_ raw: String) -> String? {
        guard !raw.isEmpty, raw.count <= 64 else { return nil }
        for scalar in raw.unicodeScalars {
            let ok = scalar == "." || (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
            if !ok { return nil }
        }
        return raw
    }

    private static let joiner: Unicode.Scalar = "\u{200D}"

    private static func dropped(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.generalCategory == .control { return true }
        if scalar == "\u{2028}" || scalar == "\u{2029}" { return true }
        if (scalar >= "\u{202A}" && scalar <= "\u{202E}") || (scalar >= "\u{2066}" && scalar <= "\u{2069}") {
            return true
        }
        switch scalar.value {
        case 0x180E, 0x200B, 0x200C, 0x200E, 0x200F, 0x2060, 0xFEFF:
            return true
        default:
            return false
        }
    }

    private static func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1F1E6...0x1F1FF, 0x1F300...0x1FAFF, 0x2600...0x26FF, 0x2700...0x27BF:
            return true
        default:
            return false
        }
    }
}

/// Pure parse of the two Focus store files. Bytes in, one reading out.
/// This type keeps no path, opens nothing and asks for no permission.
public enum SystemFocusStore {
    /// Four mebibytes. A larger file is refused before it is decoded.
    public static let maxBytes = 4 * 1024 * 1024

    /// The longest mode identifier that is still used.
    public static let maxIdentifierCharacters = 200

    /// How many modes are looked at. The rest are left unread.
    public static let maxModes = 64

    /// One Focus after cleaning. A missing name is not a missing Focus.
    public struct Mode: Equatable, Sendable {
        public var id: String?
        public var name: String?
        public var symbol: String?

        public init(id: String? = nil, name: String? = nil, symbol: String? = nil) {
            self.id = id
            self.name = name
            self.symbol = symbol
        }
    }

    /// Whether a Focus is on, off, or not yet known.
    public enum Reading: Equatable, Sendable {
        case unknown
        case off
        case on(Mode)
    }

    /// What a parse or an errno is allowed to mean.
    public enum Read: Equatable, Sendable {
        public enum Reason: Equatable, Sendable {
            /// The bytes are not the expected JSON object.
            case malformed
            /// A file is larger than the read cap.
            case tooLarge
            /// The path is not a regular file, or the folder path is not a directory.
            case notAFile
            /// The read was refused even though Full Disk Access is granted.
            case refused
            case other
        }

        case ok(Reading)
        /// The stamps match the last finished read, so the bytes were left unread.
        case unchanged
        /// Full Disk Access is missing.
        case denied
        /// The Focus store folder is absent.
        case missing
        case unreadable(Reason)
    }

    /// Which of the three checks failed.
    public enum Place: Equatable, Sendable {
        case folder
        case assertions
        case configurations
    }

    /// Decodes the assertions file and, when it names an id, the configurations file.
    /// A bad configurations file leaves the Focus on with no name. Nothing throws.
    public static func parse(assertions: Data, configurations: Data?) -> Read {
        if assertions.count > maxBytes { return .unreadable(.tooLarge) }
        if let configurations, configurations.count > maxBytes { return .unreadable(.tooLarge) }
        guard let root = jsonObject(assertions), let data = root["data"] as? [Any] else {
            return .unreadable(.malformed)
        }
        guard let records = liveRecords(in: data) else { return .unreadable(.malformed) }
        guard !records.isEmpty else { return .ok(.off) }
        guard let picked = activeIdentifier(in: records) else {
            return .ok(.on(Mode()))
        }
        return .ok(.on(mode(id: picked, configurations: configurations)))
    }

    /// Maps one errno. A configurations failure does not deny the read: the name stays nil.
    public static func read(forErrno errno: Int32, at place: Place) -> Read {
        switch place {
        case .folder:
            switch errno {
            case EPERM, EACCES: return .denied
            case ENOENT: return .missing
            case ENOTDIR, ELOOP: return .unreadable(.notAFile)
            default: return .unreadable(.other)
            }
        case .assertions:
            switch errno {
            case EPERM, EACCES: return .denied
            case ENOENT: return .ok(.off)
            case ELOOP: return .unreadable(.notAFile)
            default: return .unreadable(.other)
            }
        case .configurations:
            return .ok(.on(Mode()))
        }
    }

    /// The first `storeAssertionRecords` array. A present key of the wrong kind is malformed.
    /// Any other key, including a history list, is ignored.
    private static func liveRecords(in data: [Any]) -> [Any]? {
        for entry in data {
            guard let object = entry as? [String: Any], object.keys.contains("storeAssertionRecords") else { continue }
            guard let records = object["storeAssertionRecords"] as? [Any] else { return nil }
            return records
        }
        return []
    }

    /// The usable id with the greatest timestamp, or the first usable id when none has one.
    /// A record with no usable id is skipped. Nil when every record lacks one.
    private static func activeIdentifier(in records: [Any]) -> String? {
        struct Pick {
            var id: String
            var timestamp: Double?
        }
        var best: Pick?
        for record in records {
            guard let object = record as? [String: Any], let id = usableIdentifier(object) else { continue }
            let timestamp = finiteNumber(object["assertionStartDateTimestamp"])
            guard let current = best else {
                best = Pick(id: id, timestamp: timestamp)
                continue
            }
            switch (current.timestamp, timestamp) {
            case let (old?, new?) where new > old:
                best = Pick(id: id, timestamp: timestamp)
            case (nil, .some):
                best = Pick(id: id, timestamp: timestamp)
            default:
                break
            }
        }
        return best?.id
    }

    private static func usableIdentifier(_ record: [String: Any]) -> String? {
        guard let details = record["assertionDetails"] as? [String: Any],
              let id = details["assertionDetailsModeIdentifier"] as? String,
              !id.isEmpty,
              id.count <= maxIdentifierCharacters else { return nil }
        return id
    }

    /// `data[0].modeConfigurations` only. A bad entry leaves the others. Past 64 modes,
    /// the keys that sort first are the ones examined, because a JSON object has no stable order.
    private static func mode(id: String, configurations: Data?) -> Mode {
        guard let configurations, let root = jsonObject(configurations),
              let data = root["data"] as? [Any],
              let first = data.first as? [String: Any],
              let modes = first["modeConfigurations"] as? [String: Any] else {
            return Mode(id: id)
        }
        let examined: Set<String>
        if modes.count > maxModes {
            examined = Set(modes.keys.sorted().prefix(maxModes))
        } else {
            examined = Set(modes.keys)
        }
        guard examined.contains(id),
              let entry = modes[id] as? [String: Any],
              let mode = entry["mode"] as? [String: Any] else {
            return Mode(id: id)
        }
        let name = (mode["name"] as? String).flatMap(SystemFocusText.cleanName)
        let symbol = (mode["symbolImageName"] as? String).flatMap(SystemFocusText.cleanSymbol)
        return Mode(id: id, name: name, symbol: symbol)
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty, let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            #if canImport(CoreFoundation)
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            #endif
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if value is Bool { return nil }
        if let double = value as? Double { return double.isFinite ? double : nil }
        if let int = value as? Int { return Double(int) }
        return nil
    }
}
