import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A private recovery record. Draft bytes are retained only while a write may need reconciliation;
/// success or source invalidation erases them. An interrupted write never silently becomes a new ID.
public struct WikiExportJournal: Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public enum State: String, Codable, Sendable { case uncertain, verified, invalidated }
        public var state: State
        public let exportID: UUID
        public let destination: WikiExportDestination
        public let pageIDs: [String]
        public let sourceIDs: [String]
        public var draft: WikiExportDraft?
        public var acknowledgedSensitive: Bool
        public var relativePath: String
        public var verifiedBytes: Int?
        public var updatedAt: Date

        public init(draft: WikiExportDraft, acknowledgedSensitive: Bool, now: Date = Date()) {
            state = .uncertain
            exportID = draft.id
            destination = draft.destination
            pageIDs = draft.pages.map(\.id)
            sourceIDs = Array(Set(draft.pages.flatMap { $0.sources + $0.facts.flatMap(\.sources) + $0.contributors.map(WikiSource.meeting) }.map(\.exportIdentifier))).sorted()
            self.draft = draft
            self.acknowledgedSensitive = acknowledgedSensitive
            relativePath = draft.destination.relativePath(exportID: draft.id)
            updatedAt = now
        }

        public mutating func markVerified(bytes: Int, now: Date = Date()) {
            state = .verified
            verifiedBytes = bytes
            draft = nil
            updatedAt = now
        }

        public mutating func invalidate(now: Date = Date()) {
            state = .invalidated
            draft = nil
            acknowledgedSensitive = false
            updatedAt = now
        }
    }

    public let file: URL
    public init(file: URL) { self.file = file }

    public func load() throws -> Entry? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path) else { return nil }
        let attributes = try manager.attributesOfItem(atPath: file.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 4 * 1024 * 1024,
              (try? manager.destinationOfSymbolicLink(atPath: file.path)) == nil else {
            throw WikiExportError.destination("The export recovery record is unreadable. No new export was sent.")
        }
        return try JSONDecoder().decode(Entry.self, from: Data(contentsOf: file))
    }

    public func save(_ entry: Entry) throws {
        // Do not replace a recovery record this build cannot read.
        _ = try load()
        let manager = FileManager.default
        let directory = file.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent(".export-\(UUID().uuidString).tmp")
        let data = try JSONEncoder().encode(entry)
        guard data.count <= 4 * 1024 * 1024 else { throw WikiExportError.tooLarge }
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw WikiExportError.destination("The export recovery record could not be saved. No new export was sent.")
        }
        defer { try? manager.removeItem(at: temporary) }
        let descriptor = open(temporary.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw WikiExportError.destination("The export recovery record could not be opened.") }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw WikiExportError.destination("The export recovery record could not be saved.") }
        guard rename(temporary.path, file.path) == 0 else {
            throw WikiExportError.destination("The export recovery record could not be saved. No new export was sent.")
        }
        let folder = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if folder >= 0 { _ = fsync(folder); close(folder) }
    }

    /// Removes recoverable private content as soon as a contributing source is forgotten.
    @discardableResult
    public func invalidate(forgetting meetingIDs: Set<UUID>) throws -> Bool {
        guard var entry = try load(), entry.state == .uncertain,
              !Set(entry.sourceIDs).isDisjoint(with: Set(meetingIDs.map { "meeting:\($0.uuidString.lowercased())" })) else { return false }
        entry.invalidate()
        try save(entry)
        return true
    }
}
