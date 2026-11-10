import Foundation

/// The native export flow uses this same transaction in production and synthetic protocol tests.
/// Writes become uncertain before dispatch. A timeout never triggers a second write or a new UUID.
@MainActor
public final class WikiExportTransaction {
    public let journal: WikiExportJournal
    public private(set) var entry: WikiExportJournal.Entry?
    public private(set) var mayRetry = false

    public init(journal: WikiExportJournal) throws {
        self.journal = journal
        entry = try journal.load()
    }

    /// An older receipt must never be presented as the result of a new, failed-before-dispatch attempt.
    public func outcome(for exportID: UUID) -> WikiExportJournal.Entry? {
        guard entry?.exportID == exportID else { return nil }
        return entry
    }

    public func send(_ draft: WikiExportDraft, acknowledgedSensitive: Bool,
                     client: any WikiExportToolClient,
                     current: @MainActor () throws -> WikiExportSnapshot) async throws {
        if let entry, entry.state == .uncertain {
            guard entry.exportID == draft.id, entry.draft == draft, mayRetry else {
                throw WikiExportError.destination("Check the previous export result before sending again.")
            }
        }
        try await WikiExportMCP.discover(client)
        try Task.checkCancellation()
        try draft.validate(snapshot: current(), acknowledgedSensitive: acknowledgedSensitive)
        let pending = WikiExportJournal.Entry(draft: draft, acknowledgedSensitive: acknowledgedSensitive)
        try journal.save(pending)
        entry = pending
        mayRetry = false
        try await WikiExportMCP.create(draft, client: client)
        let result = try await WikiExportMCP.inspect(draft, client: client)
        guard case .verified(_, let bytes) = result else { throw WikiExportError.invalidResponse }
        try finishVerified(draft, bytes: bytes)
    }

    /// Inspection is deliberately separate from sending. Only an explicit missing readback permits retry.
    @discardableResult
    public func check(client: any WikiExportToolClient, current: @MainActor () throws -> WikiExportSnapshot) async throws -> WikiExportReadback {
        guard let entry, entry.state == .uncertain, let draft = entry.draft else { throw WikiExportError.staleDraft }
        try await WikiExportMCP.discover(client)
        try Task.checkCancellation()
        try draft.validate(snapshot: current(), acknowledgedSensitive: entry.acknowledgedSensitive)
        let result = try await WikiExportMCP.inspect(draft, client: client)
        switch result {
        case .missing: mayRetry = true
        case .verified(_, let bytes): try finishVerified(draft, bytes: bytes)
        }
        return result
    }

    /// Erases draft bytes on source deletion/forgetting, including when no sheet is visible.
    public func invalidate() throws {
        guard var current = try journal.load() else { return }
        entry = current
        guard current.state == .uncertain else { return }
        current.invalidate()
        try journal.save(current)
        entry = current
        mayRetry = false
    }

    private func finishVerified(_ draft: WikiExportDraft, bytes: Int) throws {
        guard var current = try journal.load(), current.state == .uncertain,
              current.exportID == draft.id, current.draft == draft else { throw WikiExportError.staleDraft }
        current.markVerified(bytes: bytes)
        try journal.save(current)
        entry = current
        mayRetry = false
    }
}
