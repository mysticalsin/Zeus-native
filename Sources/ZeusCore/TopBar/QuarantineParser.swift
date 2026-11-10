import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Extended attribute parser for `com.apple.quarantine`.
/// Standard quarantine attribute format:
/// `flags;timestamp;agent_bundle_or_name;uuid`
/// AirDrop files have an agent field mentioning `sharingd` or `AirDrop`.
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
        guard let agent = agent?.lowercased() else { return false }
        return agent == "sharingd"
            || agent == "com.apple.sharingd"
            || agent == "airdrop"
            || agent.contains("sharingd")
            || agent.contains("airdrop")
    }
}

public enum QuarantineParser {
    public static func parse(_ raw: String) -> QuarantineInfo {
        let parts = raw.components(separatedBy: ";")
        let flags = parts.indices.contains(0) ? parts[0] : ""
        let timestamp = parts.indices.contains(1) ? parts[1] : nil
        let agent = parts.indices.contains(2) ? parts[2] : nil
        let uuid = parts.indices.contains(3) ? parts[3] : nil
        return QuarantineInfo(
            raw: raw,
            flags: flags,
            timestamp: timestamp?.isEmpty == true ? nil : timestamp,
            agent: agent?.isEmpty == true ? nil : agent,
            uuid: uuid?.isEmpty == true ? nil : uuid
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
