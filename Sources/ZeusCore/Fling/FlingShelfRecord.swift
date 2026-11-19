import Foundation

public enum ShelfOrigin: Codable, Equatable, Sendable {
    case local, airDrop
    case fling(peer: String)
}

/// One persisted Shelf item that came from Fling. Local and AirDrop items are not persisted.
public struct FlingShelfRecord: Codable, Equatable, Sendable {
    public var path: String
    public var origin: ShelfOrigin
    public var stackID: UUID?
    public var verified: Bool
    public var addedAt: Date
    /// The address, for a received link kept as a `.webloc` file.
    public var link: String?
    public init(path: String, origin: ShelfOrigin, stackID: UUID?, verified: Bool, addedAt: Date, link: String?) {
        self.path = path; self.origin = origin; self.stackID = stackID; self.verified = verified; self.addedAt = addedAt; self.link = link
    }
}

struct FlingShelfFile: Codable {
    var version: Int
    var records: [FlingShelfRecord]
}

public enum FlingShelfSaveResult: Equatable, Sendable { case saved, refusedUnreadable, failed }

/// `shelf.json`: at most 500 records, written atomically with owner-only permissions. A file that cannot be read
/// is reported as unreadable and is never overwritten.
public struct FlingShelfPersistence: Sendable {
    public static let maxRecords = 500
    public static let currentVersion = 1
    public let url: URL
    public init(url: URL) { self.url = url }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .prettyPrinted]; e.dateEncodingStrategy = .secondsSince1970; return e
    }
    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }

    public func load() -> (records: [FlingShelfRecord], unreadable: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], false) }
        guard let data = try? Data(contentsOf: url), let file = try? Self.decoder().decode(FlingShelfFile.self, from: data),
              file.version <= Self.currentVersion else { return ([], true) }
        return (file.records, false)
    }

    public func save(_ records: [FlingShelfRecord]) -> FlingShelfSaveResult {
        if load().unreadable { return .refusedUnreadable }
        var kept = records
        if kept.count > Self.maxRecords {
            let newest = Set(kept.indices.sorted { kept[$0].addedAt > kept[$1].addedAt }.prefix(Self.maxRecords))
            kept = kept.indices.filter { newest.contains($0) }.map { kept[$0] }
        }
        guard let data = try? Self.encoder().encode(FlingShelfFile(version: Self.currentVersion, records: kept)) else { return .failed }
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let temp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return .failed }
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: url)
            }
            return .saved
        } catch {
            try? fm.removeItem(at: temp)
            return .failed
        }
    }
}
