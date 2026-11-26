import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Extended attribute parser for `com.apple.quarantine`.
/// Standard quarantine attribute format:
/// `flags;timestamp;agent_bundle_or_name;uuid`
/// AirDrop files have an agent field mentioning `sharingd` or `AirDrop`.
/// The fields and the AirDrop answer are read from `QuarantineParserBox`.
/// Reading the attribute still uses the file system.
public struct QuarantineInfo: Equatable, Sendable {
    public var raw: String
    public var flags: String
    public var timestamp: String?
    public var agent: String?
    public var uuid: String?

    public init(raw: String, flags: String, timestamp: String?, agent: String?, uuid: String?) {
        self.raw = raw
        self.flags = flags
        self.timestamp = timestamp
        self.agent = agent
        self.uuid = uuid
    }

    public var isAirDrop: Bool {
        QuarantineParserBox.isAirDrop(agent: agent)
    }
}

public enum QuarantineParser {
    public static func parse(_ raw: String) -> QuarantineInfo {
        let fields = QuarantineParserBox.fields(raw)
        return QuarantineInfo(
            raw: raw,
            flags: fields.flags,
            timestamp: fields.timestamp,
            agent: fields.agent,
            uuid: fields.uuid
        )
    }

    public static func isAirDrop(_ raw: String) -> Bool {
        parse(raw).isAirDrop
    }

    public static func readQuarantineString(at path: String) -> String? {
        #if canImport(Darwin)
        let name = "com.apple.quarantine"
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length + 1)
        let readLen = getxattr(path, name, &buffer, length, 0, 0)
        guard readLen > 0 else { return nil }
        return String(cString: buffer)
        #else
        return nil
        #endif
    }

    public static func isAirDropFile(at url: URL) -> Bool {
        guard let quarantine = readQuarantineString(at: url.path) else { return false }
        return isAirDrop(quarantine)
    }
}
