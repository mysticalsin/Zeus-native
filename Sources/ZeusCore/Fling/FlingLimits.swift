import Foundation

/// Every cap Fling enforces, in one place so the rules and their tests agree.
public enum FlingLimits {
    public static let protocolVersion = 1
    public static let maxItems = 100
    /// A JSON header frame (offer, hello, pairing messages) is at most 64 KiB.
    public static let maxHeaderPayloadBytes = 64 * 1024
    /// A chunk frame (4-byte index plus data) is at most 1 MiB.
    public static let maxChunkPayloadBytes = 1024 * 1024
    /// The data size a sender puts in one chunk.
    public static let sendChunkBytes = 256 * 1024
    public static let maxLinkLength = 2048
    /// One item may declare at most this many bytes (1 TiB); with 100 items the total still fits an Int64.
    public static let maxItemBytes: Int64 = 1 << 40
    /// A new card ignores clicks for this long, so a stray or scripted click cannot answer it.
    public static let promptInputDelay: TimeInterval = 1
    /// After the hello, each pairing step must arrive within this time.
    public static let pairingStageTimeout: TimeInterval = 10
    public static let maxNameBytes = 255
    /// Free space that must remain after an arrival.
    public static let freeSpaceReserveBytes: Int64 = 1024 * 1024 * 1024
    /// Above this total the sender is warned before sending.
    public static let warnTotalBytes: Int64 = 2_000_000_000
    public static let maxConnections = 8
    public static let handshakeTimeout: TimeInterval = 10
    public static let idleTimeout: TimeInterval = 30
    /// An accept prompt or a pairing code waits this long, then counts as a decline.
    public static let promptTimeout: TimeInterval = 60
    /// A stack id is remembered this long; a repeat is declined as a replay.
    public static let replayWindow: TimeInterval = 10 * 60

    public static func shouldWarn(totalBytes: Int64) -> Bool { totalBytes > warnTotalBytes }
}
