import Foundation

/// The four fields of a `com.apple.quarantine` attribute, and whether the agent names AirDrop.
/// Flags stay as written, including when they are empty. An empty timestamp, agent, or uuid is absent.
/// A field after the uuid is ignored. AirDrop is an agent of sharingd, com.apple.sharingd, or airdrop,
/// or any agent that contains those words. The match ignores case and keeps surrounding spaces.
/// This type does not read a file, a screen, a pointer, a clock, or a stored setting.
public enum QuarantineParserBox {
    public struct Fields: Equatable, Sendable {
        public var flags: String
        public var timestamp: String?
        public var agent: String?
        public var uuid: String?
    }

    /// `flags;timestamp;agent;uuid`.
    public static func fields(_ raw: String) -> Fields {
        let parts = raw.components(separatedBy: ";")
        func optional(_ index: Int) -> String? {
            guard parts.indices.contains(index) else { return nil }
            let value = parts[index]
            return value.isEmpty ? nil : value
        }
        return Fields(
            flags: parts.indices.contains(0) ? parts[0] : "",
            timestamp: optional(1),
            agent: optional(2),
            uuid: optional(3)
        )
    }

    /// sharingd, com.apple.sharingd, airdrop, or an agent that contains those words.
    public static func isAirDrop(agent: String?) -> Bool {
        guard let agent = agent?.lowercased() else { return false }
        return agent == "sharingd"
            || agent == "com.apple.sharingd"
            || agent == "airdrop"
            || agent.contains("sharingd")
            || agent.contains("airdrop")
    }
}
