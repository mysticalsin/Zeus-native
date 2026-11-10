import Foundation

/// The recovery journal for a lid-closed session: written BEFORE every system change, so a crash,
/// a force quit or a dead battery can always be undone, by Zeus at its next launch or by the
/// `zeus insomnia-guard` backstop launchd runs every minute.
/// The journal idea comes from Insomnia (MIT, Krish Garg and contributors); the format is ours.
public struct InsomniaJournal: Codable, Equatable, Sendable {
    public static let fileName = "insomnia-journal.json"

    /// One change Zeus made, with what puts it back.
    public enum Change: Codable, Equatable, Sendable {
        /// `pmset -a disablesleep 1` ran; `previous` is what SleepDisabled read before.
        case disableSleep(previous: Bool)
        /// `pmset -a lowpowermode 1` ran; `previous` is the mode before.
        case lowPowerMode(previous: Bool)
        /// SIGSTOP was sent to this process.
        case frozen(pid: Int32, bundleID: String)
        /// The output was muted; the volume (0 to 100) and mute state before.
        case audio(volume: Int, muted: Bool)

        /// Changes of one kind replace each other, so the journal keeps the first "before" value.
        var key: String {
            switch self {
            case .disableSleep: "disableSleep"
            case .lowPowerMode: "lowPowerMode"
            case .frozen(let pid, _): "frozen.\(pid)"
            case .audio: "audio"
            }
        }
    }

    public var sessionID: UUID
    public var start: Date
    /// Nil for an Indefinitely session.
    public var plannedEnd: Date?
    public var zeusPID: Int32
    /// The running Zeus binary, so a reused pid is not taken for Zeus.
    public var zeusExecutable: String?
    public var changes: [Change]

    public init(sessionID: UUID = UUID(), start: Date, plannedEnd: Date?, zeusPID: Int32,
                zeusExecutable: String? = nil, changes: [Change] = []) {
        self.sessionID = sessionID
        self.start = start
        self.plannedEnd = plannedEnd
        self.zeusPID = zeusPID
        self.zeusExecutable = zeusExecutable
        self.changes = changes
    }

    /// Adds a change unless one of the same kind is already there: the oldest "before" wins.
    public mutating func record(_ change: Change) {
        guard !changes.contains(where: { $0.key == change.key }) else { return }
        changes.append(change)
    }

    /// Forgets a change once it has been put back (lid opened, apps thawed).
    public mutating func forget(_ change: Change) {
        changes.removeAll { $0.key == change.key }
    }

    public var frozenPIDs: [Int32] {
        changes.compactMap { if case .frozen(let pid, _) = $0 { pid } else { nil } }
    }
}

/// Where the journal lives. Injected so tests never touch the real support folder.
public protocol InsomniaFileStore: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func remove() throws
}

/// The journal file, owner-only (0600), replaced atomically.
public struct InsomniaDiskStore: InsomniaFileStore {
    public let url: URL

    public init(url: URL = ZeusPaths.insomniaJournal) {
        self.url = url
    }

    public func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

/// In memory, for tests and previews.
public final class InsomniaMemoryStore: InsomniaFileStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    public private(set) var writes = 0

    public init(_ data: Data? = nil) { self.data = data }

    public func read() throws -> Data? { lock.withLock { data } }
    public func write(_ data: Data) throws { lock.withLock { self.data = data; writes += 1 } }
    public func remove() throws { lock.withLock { data = nil } }
}

/// Reads and writes the journal as JSON.
public struct InsomniaJournalStore: Sendable {
    public let files: any InsomniaFileStore

    public init(files: any InsomniaFileStore = InsomniaDiskStore()) {
        self.files = files
    }

    /// Nil when there is no journal, or it cannot be read (an unreadable journal is reported, not trusted).
    public func load() -> InsomniaJournal? {
        guard let data = try? files.read() else { return nil }
        return try? Self.decoder.decode(InsomniaJournal.self, from: data)
    }

    /// True when a file exists, readable or not.
    public var exists: Bool { ((try? files.read()) ?? nil) != nil }

    public func save(_ journal: InsomniaJournal) throws {
        try files.write(try Self.encoder.encode(journal))
    }

    public func clear() throws { try files.remove() }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
