import Foundation

/// RAM-only pointing session memory.
///
/// Snapshots stay in this value: at most three, each at most 8 MiB, and only for ten minutes.
/// A pointing session record uses the 24 hour retention from the pointing plan. Nothing here is
/// written to a file. Rows go away at session end, quit, feature-off, or delete.
public struct PointingSessionMemory: Equatable, Sendable {
    public static let snapshotLimit = 3
    public static let snapshotByteLimit = 8 * 1024 * 1024
    public static let snapshotRetention: TimeInterval = 10 * 60
    public static let sessionRetention: TimeInterval = 24 * 60 * 60

    public struct Session: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let startedAt: Date
        public let endedAt: Date?
        public var isOpen: Bool { endedAt == nil }

        public init(id: UUID, startedAt: Date, endedAt: Date? = nil) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
        }
    }

    public struct Snapshot: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let sessionID: UUID
        public let capturedAt: Date
        public let bytes: Data
        public var byteCount: Int { bytes.count }

        public init(id: UUID, sessionID: UUID, capturedAt: Date, bytes: Data) {
            self.id = id
            self.sessionID = sessionID
            self.capturedAt = capturedAt
            self.bytes = bytes
        }
    }

    public struct Listing: Equatable, Sendable {
        public var sessions: [Session]
        public var snapshots: [Snapshot]

        public init(sessions: [Session] = [], snapshots: [Snapshot] = []) {
            self.sessions = sessions
            self.snapshots = snapshots
        }
    }

    public enum RememberResult: Equatable, Sendable {
        case stored
        case rejectedDisabled
        case rejectedEmpty
        case rejectedTooLarge
        case rejectedNoSession
        case rejectedDuplicate
        case rejectedClock
    }

    public enum BeginResult: Equatable, Sendable {
        case started
        case rejectedDisabled
        case rejectedDuplicate
        case rejectedClock
    }

    public private(set) var enabled: Bool
    private var sessions: [Session] = []
    private var snapshots: [Snapshot] = []

    public init(enabled: Bool = true) {
        self.enabled = enabled
    }

    public mutating func beginSession(id: UUID, at date: Date) -> BeginResult {
        guard enabled else { return .rejectedDisabled }
        guard date.timeIntervalSince1970.isFinite else { return .rejectedClock }
        sweep(now: date)
        if identifierIsInUse(id) { return .rejectedDuplicate }
        sessions.append(Session(id: id, startedAt: date, endedAt: nil))
        return .started
    }

    /// Ends one session and drops its snapshots. A clock at or after the start is required.
    /// A second end leaves the first end time in place.
    @discardableResult
    public mutating func endSession(_ id: UUID, at date: Date) -> Bool {
        guard date.timeIntervalSince1970.isFinite else { return false }
        sweep(now: date)
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return false }
        let session = sessions[index]
        guard session.endedAt == nil, date >= session.startedAt else { return false }
        sessions[index] = Session(id: session.id, startedAt: session.startedAt, endedAt: date)
        snapshots.removeAll { $0.sessionID == id }
        return true
    }

    /// Keeps a capture for an open session. A refused payload does not change stored rows.
    /// The snapshot just stored is kept; an older one is dropped when the store is past three.
    public mutating func rememberSnapshot(id: UUID, bytes: Data, sessionID: UUID, at date: Date) -> RememberResult {
        guard enabled else { return .rejectedDisabled }
        guard date.timeIntervalSince1970.isFinite else { return .rejectedClock }
        guard !bytes.isEmpty else { return .rejectedEmpty }
        guard bytes.count <= Self.snapshotByteLimit else { return .rejectedTooLarge }
        sweep(now: date)
        if identifierIsInUse(id) { return .rejectedDuplicate }
        guard sessions.contains(where: { $0.id == sessionID && $0.isOpen }) else { return .rejectedNoSession }
        snapshots.append(Snapshot(id: id, sessionID: sessionID, capturedAt: date, bytes: bytes))
        trimSnapshots(keeping: id)
        return .stored
    }

    /// Removes one snapshot, or one session and that session's snapshots.
    @discardableResult
    public mutating func delete(id: UUID, at date: Date) -> Bool {
        guard date.timeIntervalSince1970.isFinite else { return false }
        sweep(now: date)
        if let index = snapshots.firstIndex(where: { $0.id == id }) {
            snapshots.remove(at: index)
            return true
        }
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            let sessionID = sessions[index].id
            sessions.remove(at: index)
            snapshots.removeAll { $0.sessionID == sessionID }
            return true
        }
        return false
    }

    /// Feature off. Stored rows are dropped and stay dropped after a later `enable()`.
    public mutating func disable() {
        enabled = false
        sessions.removeAll()
        snapshots.removeAll()
    }

    public mutating func enable() {
        enabled = true
    }

    /// Process quit. Stored rows are dropped. The enabled flag stays as it was.
    public mutating func quit() {
        sessions.removeAll()
        snapshots.removeAll()
    }

    /// Drops expired rows when `date` is finite, then returns newest sessions and snapshots first.
    /// A non-finite clock returns the rows already stored and does not drop them.
    public mutating func list(at date: Date) -> Listing {
        guard date.timeIntervalSince1970.isFinite else {
            return Listing(sessions: listedSessions(), snapshots: listedSnapshots())
        }
        sweep(now: date)
        return Listing(sessions: listedSessions(), snapshots: listedSnapshots())
    }

    private func identifierIsInUse(_ id: UUID) -> Bool {
        sessions.contains { $0.id == id } || snapshots.contains { $0.id == id }
    }

    private mutating func sweep(now: Date) {
        sessions.removeAll { session in
            !session.startedAt.timeIntervalSince1970.isFinite
                || now.timeIntervalSince(session.startedAt) >= Self.sessionRetention
        }
        let live = Set(sessions.map(\.id))
        snapshots.removeAll { snapshot in
            !live.contains(snapshot.sessionID)
                || !snapshot.capturedAt.timeIntervalSince1970.isFinite
                || now.timeIntervalSince(snapshot.capturedAt) >= Self.snapshotRetention
        }
    }

    private mutating func trimSnapshots(keeping id: UUID) {
        while snapshots.count > Self.snapshotLimit {
            guard let index = oldestSnapshotIndex(excluding: id) else { return }
            snapshots.remove(at: index)
        }
    }

    private func oldestSnapshotIndex(excluding id: UUID) -> Int? {
        snapshots.indices.filter { snapshots[$0].id != id }.min { lhs, rhs in
            if snapshots[lhs].capturedAt != snapshots[rhs].capturedAt {
                return snapshots[lhs].capturedAt < snapshots[rhs].capturedAt
            }
            return lhs < rhs
        }
    }

    private func listedSessions() -> [Session] {
        sessions.enumerated().sorted { lhs, rhs in
            if lhs.element.startedAt != rhs.element.startedAt {
                return lhs.element.startedAt > rhs.element.startedAt
            }
            return lhs.offset > rhs.offset
        }.map(\.element)
    }

    private func listedSnapshots() -> [Snapshot] {
        snapshots.enumerated().sorted { lhs, rhs in
            if lhs.element.capturedAt != rhs.element.capturedAt {
                return lhs.element.capturedAt > rhs.element.capturedAt
            }
            return lhs.offset > rhs.offset
        }.map(\.element)
    }
}
