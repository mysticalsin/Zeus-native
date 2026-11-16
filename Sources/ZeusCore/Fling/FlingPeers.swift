import Foundation

public struct FlingPeerEntry: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var model: String
    public var paired: Bool
}

/// The Macs seen nearby. A peer is listed for ten seconds after it was last seen.
public struct FlingPeerList: Sendable {
    public static let freshness: TimeInterval = 10
    private struct Seen: Sendable { var name: String; var model: String; var lastSeen: Date }
    private var seenPeers: [String: Seen] = [:]
    private var pairedNames: [String: String] = [:]
    public init() {}

    public mutating func seen(id: String, name: String, model: String, now: Date) {
        seenPeers[id] = Seen(name: name, model: model, lastSeen: now)
    }
    public mutating func lost(id: String) { seenPeers[id] = nil }
    /// Paired Macs are shown by the name stored at pairing, never by what they advertise.
    public mutating func setPaired(_ names: [String: String]) { pairedNames = names }

    public func visible(now: Date) -> [FlingPeerEntry] {
        seenPeers
            .filter { now.timeIntervalSince($0.value.lastSeen) <= Self.freshness }
            .map { FlingPeerEntry(id: $0.key, name: pairedNames[$0.key] ?? $0.value.name, model: $0.value.model, paired: pairedNames[$0.key] != nil) }
            .sorted {
                if $0.paired != $1.paired { return $0.paired }
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
    }
}

/// At most eight connections, and one active transfer per peer.
public struct FlingConnectionGate: Sendable {
    private var connections: Set<Int> = []
    private var transfers: Set<String> = []
    public init() {}
    public mutating func admit(connection: Int) -> Bool {
        if connections.contains(connection) { return true }
        guard connections.count < FlingLimits.maxConnections else { return false }
        connections.insert(connection)
        return true
    }
    public mutating func release(connection: Int) { connections.remove(connection) }
    public mutating func beginTransfer(peerID: String) -> Bool { transfers.insert(peerID).inserted }
    public mutating func endTransfer(peerID: String) { transfers.remove(peerID) }
}

public struct FlingTimeoutPolicy: Sendable {
    public var connectedAt: Date
    public var lastActivity: Date
    public init(connectedAt: Date, lastActivity: Date) { self.connectedAt = connectedAt; self.lastActivity = lastActivity }
    /// 10 s to finish the handshake, then 30 s without traffic.
    public func shouldClose(now: Date, handshaken: Bool) -> Bool {
        handshaken ? now.timeIntervalSince(lastActivity) >= FlingLimits.idleTimeout
                   : now.timeIntervalSince(connectedAt) >= FlingLimits.handshakeTimeout
    }
}

public enum FlingVisibility: String, CaseIterable, Codable, Sendable {
    case everyone, pairedOnly, off
}

public struct FlingVisibilityPlan: Equatable, Sendable {
    public var advertise: Bool
    public var transferListener: Bool
    public var pairingListener: Bool
    public var txt: [String: String]
}

public enum FlingVisibilityPolicy {
    public static func plan(visibility: FlingVisibility, id: String, name: String, model: String, pairPort: UInt16) -> FlingVisibilityPlan {
        let v = String(FlingLimits.protocolVersion)
        switch visibility {
        case .everyone:
            return FlingVisibilityPlan(advertise: true, transferListener: true, pairingListener: true,
                                       txt: ["v": v, "id": id, "name": name, "model": model, "pp": String(pairPort)])
        case .pairedOnly:
            return FlingVisibilityPlan(advertise: true, transferListener: true, pairingListener: false, txt: ["v": v, "id": id])
        case .off:
            return FlingVisibilityPlan(advertise: false, transferListener: false, pairingListener: false, txt: [:])
        }
    }
}

/// A stack id is remembered for ten minutes from its first sighting; a repeat inside that time is a replay.
public struct FlingReplayLedger: Sendable {
    private var firstSeen: [UUID: Date] = [:]
    public init() {}
    public mutating func isReplay(_ id: UUID, now: Date) -> Bool {
        firstSeen = firstSeen.filter { now.timeIntervalSince($0.value) <= FlingLimits.replayWindow }
        if firstSeen[id] != nil { return true }
        firstSeen[id] = now
        return false
    }
}
