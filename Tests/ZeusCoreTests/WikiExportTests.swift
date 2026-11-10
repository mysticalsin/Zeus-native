import Foundation
import Testing
@testable import ZeusCore

private final class ExportFixture {
    let root: URL
    let sourceID = UUID()
    let now = Date(timeIntervalSince1970: 1_000)
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-export-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    var connection: BrainConnection {
        BrainConnection(source: BrainSource(kind: .obsidian, name: "Synthetic vault", path: root.path), access: .readWrite)
    }
    var page: WikiPage {
        WikiPage(id: "chosen", title: "Chosen decision", body: "Keep the launch small.",
                 sources: [.meeting(sourceID)], updatedAt: now, contributors: [sourceID])
    }
    func snapshot(pages: [WikiPage]? = nil, connection: BrainConnection? = nil,
                  available: Set<UUID>? = nil, forgotten: Set<UUID> = [], readable: Bool = true) -> WikiExportSnapshot {
        WikiExportSnapshot(pages: pages ?? [page], connection: connection ?? self.connection,
            availableMeetingIDs: available ?? [sourceID], forgottenMeetingIDs: forgotten,
            sourceTitles: [sourceID: "Synthetic planning"], settingsReadable: readable)
    }
    func draft() throws -> WikiExportDraft { try .make(selectedIDs: [page.id], snapshot: snapshot(), now: now) }
    func vault() throws -> WikiExportVault {
        try WikiExportVault(root: root, inbox: connection.inboxFolder, expectedIdentity: WikiExportVault.identity(of: root))
    }
    var journal: WikiExportJournal { WikiExportJournal(file: root.appendingPathComponent("private/recovery.json")) }
}

private actor LocalExportClient: WikiExportToolClient {
    enum Failure { case none, beforeCreate, afterCreate, incompatibleDiscovery }
    private var server: WikiExportMCPServer
    var failure: Failure
    private var nextID = 10
    private(set) var writes = 0
    private(set) var reads = 0
    init(vault: WikiExportVault, failure: Failure = .none) throws {
        self.failure = failure
        server = WikiExportMCPServer(vault: vault)
        _ = server.handle(MCPCodec.request(id: 1, method: "initialize", params: MCPCodec.initializeParams()))
        _ = server.handle(MCPCodec.notification(method: "notifications/initialized"))
    }
    func setFailure(_ failure: Failure) { self.failure = failure }
    func exportTools() async throws -> [MCPToolInfo] {
        if failure == .incompatibleDiscovery { return [] }
        return MCPToolInfo.parse(try invoke("tools/list", params: .object([:])))
    }
    func exportCall(_ name: String, arguments: [String: JSONValue]) async throws -> MCPToolResult {
        if name == WikiExportMCP.createTool {
            writes += 1
            if failure == .beforeCreate { throw CancellationError() }
        } else { reads += 1 }
        let result = try invoke("tools/call", params: MCPCodec.callParams(name: name, arguments: arguments))
        if name == WikiExportMCP.createTool, failure == .afterCreate { throw CancellationError() }
        return try #require(MCPToolResult(result: result))
    }
    private func invoke(_ method: String, params: JSONValue) throws -> JSONValue? {
        nextID += 1
        let reply = server.handle(MCPCodec.request(id: nextID, method: method, params: params))
        let bytes = try #require(reply)
        guard case .response(_, let result, let error) = try MCPCodec.decode(bytes) else { throw WikiExportError.invalidResponse }
        if let error { throw error }
        return result
    }
}

@Suite("Selected Memory MCP exports")
struct WikiExportTests {
    @Test func selectionPreviewContainsOnlyReviewedPagesAndStableProvenance() throws {
        let f = try ExportFixture()
        let other = WikiPage(id: "other", title: "Unselected", body: "Do not export this", updatedAt: f.now)
        let draft = try WikiExportDraft.make(selectedIDs: [f.page.id], snapshot: f.snapshot(pages: [other, f.page]), now: f.now)
        #expect(draft.pages == [f.page])
        #expect(draft.markdown.contains("Keep the launch small."))
        #expect(draft.markdown.contains("meeting:\(f.sourceID.uuidString.lowercased())"))
        #expect(!draft.markdown.contains("Do not export this"))
        #expect(!draft.markdown.contains(f.root.path))
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("ZEUS").path))
    }

    @Test func emptyMissingAndTooManySelectionsAreRejected() throws {
        let f = try ExportFixture()
        #expect(throws: (any Error).self) { try WikiExportDraft.make(selectedIDs: [], snapshot: f.snapshot()) }
        #expect(throws: WikiExportError.staleDraft) { try WikiExportDraft.make(selectedIDs: ["missing"], snapshot: f.snapshot()) }
        #expect(throws: (any Error).self) {
            try WikiExportDraft.make(selectedIDs: Set((0...20).map(String.init)), snapshot: f.snapshot())
        }
    }

    @Test func explicitWritableDestinationIsRequired() throws {
        let f = try ExportFixture()
        var connection = f.connection
        connection.access = .readOnly
        #expect(throws: (any Error).self) { try WikiExportDraft.make(selectedIDs: [f.page.id], snapshot: f.snapshot(connection: connection)) }
        connection.access = .readWrite
        connection.source.kind = .notion
        #expect(throws: (any Error).self) { try WikiExportDestination(connection: connection) }
        let noDestination = WikiExportSnapshot(pages: [f.page], connection: nil, availableMeetingIDs: [f.sourceID],
            forgottenMeetingIDs: [], sourceTitles: [:], settingsReadable: true)
        #expect(throws: (any Error).self) { try WikiExportDraft.make(selectedIDs: [f.page.id], snapshot: noDestination) }
    }

    @Test func sourceReviewForgettingAvailabilityAndSettingsFailClosed() throws {
        let f = try ExportFixture()
        var page = f.page
        page.needsReview = true
        #expect(throws: WikiExportError.needsReview) { try WikiExportDraft.make(selectedIDs: [page.id], snapshot: f.snapshot(pages: [page])) }
        for snapshot in [f.snapshot(available: []), f.snapshot(forgotten: [f.sourceID]), f.snapshot(readable: false)] {
            #expect(throws: WikiExportError.needsReview) { try WikiExportDraft.make(selectedIDs: [f.page.id], snapshot: snapshot) }
        }
        page = f.page
        page.sources = []
        #expect(throws: WikiExportError.needsReview) {
            try WikiExportDraft.make(selectedIDs: [page.id], snapshot: f.snapshot(pages: [page], forgotten: [f.sourceID]))
        }
    }

    @Test func immutableRevisionAndDestinationAreRechecked() throws {
        let f = try ExportFixture(), draft = try f.draft()
        var page = f.page
        page.body += " Changed after review."
        #expect(throws: WikiExportError.staleDraft) { try draft.validate(snapshot: f.snapshot(pages: [page]), acknowledgedSensitive: true) }
        var connection = f.connection
        connection.inboxFolder = "Different"
        #expect(throws: WikiExportError.staleDraft) { try draft.validate(snapshot: f.snapshot(connection: connection), acknowledgedSensitive: true) }
    }

    @Test func sensitiveReviewCannotBeSkipped() throws {
        let f = try ExportFixture()
        var page = f.page
        page.body = "Email jane@example.com about this."
        let draft = try WikiExportDraft.make(selectedIDs: [page.id], snapshot: f.snapshot(pages: [page]))
        #expect(draft.sensitiveFindingCount > 0)
        #expect(throws: WikiExportError.sensitiveReview) { try draft.validate(snapshot: f.snapshot(pages: [page]), acknowledgedSensitive: false) }
        try draft.validate(snapshot: f.snapshot(pages: [page]), acknowledgedSensitive: true)
    }

    @Test func oversizedPreviewIsRejected() throws {
        let f = try ExportFixture()
        var page = f.page
        page.body = String(repeating: "x", count: WikiExportDraft.maxBytes)
        #expect(throws: WikiExportError.tooLarge) { try WikiExportDraft.make(selectedIDs: [page.id], snapshot: f.snapshot(pages: [page])) }
    }

    @Test func rootReplacementIsRejected() throws {
        let f = try ExportFixture(), draft = try f.draft()
        let moved = f.root.appendingPathExtension("old")
        defer { try? FileManager.default.removeItem(at: moved) }
        try FileManager.default.moveItem(at: f.root, to: moved)
        try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: true)
        #expect(throws: WikiExportError.staleDraft) { try draft.validate(snapshot: f.snapshot(), acknowledgedSensitive: true) }
        #expect(throws: WikiExportError.staleDraft) {
            try WikiExportVault(root: f.root, inbox: "Inbox", expectedIdentity: draft.destination.rootIdentity)
        }
    }

    @Test func traversalHiddenAndAbsoluteInboxPathsAreRejected() throws {
        for path in ["", "/tmp", "../outside", "ZEUS/../outside", ".obsidian", "ZEUS//Inbox", "ZEUS/\\bad", "ZEUS/\nInbox"] {
            #expect(throws: (any Error).self) { try WikiExportVault.validateInbox(path) }
        }
    }

    @Test func readbackDoesNotCreateFoldersAndCreateIsExactAndIdempotent() throws {
        let f = try ExportFixture(), vault = try f.vault(), id = UUID()
        #expect(try vault.inspect(exportID: id) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
        let text = "# Exact\nRésumé 🦉\n"
        try vault.create(exportID: id, markdown: text)
        try vault.create(exportID: id, markdown: text)
        #expect(try vault.inspect(exportID: id) == text)
        let directory = f.root.appendingPathComponent(f.connection.inboxFolder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [WikiExportVault.fileName(id)])
        let attrs = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(WikiExportVault.fileName(id)).path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func collisionsNeverOverwriteAnExistingNote() throws {
        let f = try ExportFixture(), vault = try f.vault(), id = UUID()
        try vault.create(exportID: id, markdown: "Original")
        #expect(throws: WikiExportError.conflict) { try vault.create(exportID: id, markdown: "Changed") }
        #expect(try vault.inspect(exportID: id) == "Original")
    }

    @Test func symbolicInboxAndFileLinksCannotRedirectWritesOrReads() throws {
        let f = try ExportFixture(), outside = try ExportFixture(), id = UUID()
        let first = f.root.appendingPathComponent("ZEUS")
        try FileManager.default.createSymbolicLink(at: first, withDestinationURL: outside.root)
        let vault = try f.vault()
        #expect(throws: (any Error).self) { try vault.create(exportID: id, markdown: "Secret") }
        #expect(throws: (any Error).self) { try vault.inspect(exportID: id) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.root.path).isEmpty)
        try FileManager.default.removeItem(at: first)
        let folder = f.root.appendingPathComponent(f.connection.inboxFolder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = outside.root.appendingPathComponent("private.md")
        try "Outside".write(to: target, atomically: false, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(WikiExportVault.fileName(id)), withDestinationURL: target)
        #expect(throws: (any Error).self) { try vault.create(exportID: id, markdown: "Secret") }
        #expect(throws: (any Error).self) { try vault.inspect(exportID: id) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "Outside")
    }

    @Test func protocolRequiresHandshakeAndAcceptsOnlyBoundedTools() throws {
        let f = try ExportFixture()
        var server = WikiExportMCPServer(vault: try f.vault())
        let prematureReply = server.handle(MCPCodec.request(id: 1, method: "tools/list"))
        let premature = try #require(prematureReply)
        if case .response(_, _, let error) = try MCPCodec.decode(premature) { #expect(error != nil) }
        _ = server.handle(MCPCodec.request(id: 2, method: "initialize", params: MCPCodec.initializeParams()))
        _ = server.handle(MCPCodec.notification(method: "notifications/initialized"))
        let params = MCPCodec.callParams(name: WikiExportMCP.createTool, arguments: ["export_id": .string(UUID().uuidString),
            "markdown": .string("No"), "path": .string("outside.md")])
        let extraArgumentReply = server.handle(MCPCodec.request(id: 3, method: "tools/call", params: params))
        let reply = try #require(extraArgumentReply)
        if case .response(_, _, let error) = try MCPCodec.decode(reply) { #expect(error?.code == -32_602) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
    }

    @Test func hardlinkedUUIDNoteCannotExposeAnUnrelatedFile() throws {
        let f = try ExportFixture(), outside = try ExportFixture(), id = UUID()
        let directory = f.root.appendingPathComponent(f.connection.inboxFolder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = outside.root.appendingPathComponent("private.md")
        try "Unrelated private text".write(to: original, atomically: false, encoding: .utf8)
        try FileManager.default.linkItem(at: original, to: directory.appendingPathComponent(WikiExportVault.fileName(id)))
        let vault = try f.vault()
        #expect(throws: WikiExportError.conflict) { try vault.inspect(exportID: id) }
        #expect(throws: WikiExportError.conflict) { try vault.create(exportID: id, markdown: "New") }
        #expect(try String(contentsOf: original, encoding: .utf8) == "Unrelated private text")
    }

    @Test @MainActor func realProtocolSelectionTransactionVerifiesAndErasesRecoveryBytes() async throws {
        let f = try ExportFixture(), draft = try f.draft()
        let client = try LocalExportClient(vault: f.vault())
        let transaction = try WikiExportTransaction(journal: f.journal)
        try await transaction.send(draft, acknowledgedSensitive: true, client: client, current: { f.snapshot() })
        #expect(transaction.entry?.state == .verified)
        #expect(transaction.entry?.draft == nil)
        #expect(await client.writes == 1)
        #expect(await client.reads == 1)
        #expect(try f.vault().inspect(exportID: draft.id) == draft.markdown)
        #expect(!(try String(contentsOf: f.journal.file, encoding: .utf8)).contains("Keep the launch small"))
    }

    @Test @MainActor func incompatibleDiscoveryAndChangedReviewPerformNoWrites() async throws {
        let f = try ExportFixture(), draft = try f.draft()
        let client = try LocalExportClient(vault: f.vault(), failure: .incompatibleDiscovery)
        let transaction = try WikiExportTransaction(journal: f.journal)
        await #expect(throws: WikiExportError.protocolMismatch) {
            try await transaction.send(draft, acknowledgedSensitive: true, client: client, current: { f.snapshot() })
        }
        await client.setFailure(.none)
        await #expect(throws: WikiExportError.needsReview) {
            try await transaction.send(draft, acknowledgedSensitive: true, client: client, current: { f.snapshot(forgotten: [f.sourceID]) })
        }
        #expect(await client.writes == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
    }

    @Test @MainActor func lostCreateReplyRequiresReadOnlyReconciliationAndNeverDuplicates() async throws {
        let f = try ExportFixture(), draft = try f.draft()
        let client = try LocalExportClient(vault: f.vault(), failure: .afterCreate)
        let transaction = try WikiExportTransaction(journal: f.journal)
        await #expect(throws: CancellationError.self) {
            try await transaction.send(draft, acknowledgedSensitive: true, client: client, current: { f.snapshot() })
        }
        #expect(transaction.entry?.state == .uncertain)
        #expect(!transaction.mayRetry)
        await #expect(throws: (any Error).self) {
            try await transaction.send(draft, acknowledgedSensitive: true, client: client, current: { f.snapshot() })
        }
        let recovered = try WikiExportTransaction(journal: f.journal)
        let result = try await recovered.check(client: client, current: { f.snapshot() })
        #expect(result == .verified(relativePath: draft.destination.relativePath(exportID: draft.id), bytes: draft.markdown.utf8.count))
        #expect(await client.writes == 1)
        #expect(recovered.entry?.draft == nil)
    }

    @Test @MainActor func missingReadbackPermitsOnlyTheSameImmutableRetry() async throws {
        let f = try ExportFixture(), draft = try f.draft()
        let client = try LocalExportClient(vault: f.vault(), failure: .beforeCreate)
        let transaction = try WikiExportTransaction(journal: f.journal)
        await #expect(throws: CancellationError.self) {
            try await transaction.send(draft, acknowledgedSensitive: true, client: client, current: { f.snapshot() })
        }
        #expect(try await transaction.check(client: client, current: { f.snapshot() }) == .missing)
        #expect(transaction.mayRetry)
        let replacement = try f.draft()
        await #expect(throws: (any Error).self) {
            try await transaction.send(replacement, acknowledgedSensitive: true, client: client, current: { f.snapshot() })
        }
        await client.setFailure(.none)
        try await transaction.send(draft, acknowledgedSensitive: true, client: client, current: { f.snapshot() })
        #expect(transaction.entry?.exportID == draft.id)
        #expect(transaction.entry?.state == .verified)
    }

    @Test @MainActor func changedReadbackIsAConflictAndNeverReplaced() async throws {
        let f = try ExportFixture(), draft = try f.draft()
        let client = try LocalExportClient(vault: f.vault(), failure: .afterCreate)
        let transaction = try WikiExportTransaction(journal: f.journal)
        await #expect(throws: CancellationError.self) {
            try await transaction.send(draft, acknowledgedSensitive: true, client: client, current: { f.snapshot() })
        }
        let file = f.root.appendingPathComponent(draft.destination.relativePath(exportID: draft.id))
        try "Edited in Obsidian".write(to: file, atomically: false, encoding: .utf8)
        await #expect(throws: WikiExportError.conflict) { try await transaction.check(client: client, current: { f.snapshot() }) }
        #expect(!transaction.mayRetry)
        #expect(try String(contentsOf: file, encoding: .utf8) == "Edited in Obsidian")
        #expect(await client.writes == 1)
    }

    @Test @MainActor func forgettingErasesPendingContentAndBlocksRecovery() async throws {
        let f = try ExportFixture(), draft = try f.draft()
        try f.journal.save(.init(draft: draft, acknowledgedSensitive: true))
        let transaction = try WikiExportTransaction(journal: f.journal)
        #expect(try f.journal.invalidate(forgetting: [f.sourceID]))
        try transaction.invalidate()
        #expect(transaction.entry?.state == .invalidated)
        #expect(transaction.entry?.draft == nil)
        #expect(!(try String(contentsOf: f.journal.file, encoding: .utf8)).contains("Keep the launch small"))
        let client = try LocalExportClient(vault: f.vault())
        await #expect(throws: WikiExportError.staleDraft) { try await transaction.check(client: client, current: { f.snapshot() }) }
        #expect(await client.writes == 0)
        #expect(await client.reads == 0)
    }

    @Test func corruptRecoveryRecordBlocksReplacement() throws {
        let f = try ExportFixture(), draft = try f.draft()
        try FileManager.default.createDirectory(at: f.journal.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "corrupt".write(to: f.journal.file, atomically: false, encoding: .utf8)
        #expect(throws: (any Error).self) { try f.journal.save(.init(draft: draft, acknowledgedSensitive: true)) }
        #expect(try String(contentsOf: f.journal.file, encoding: .utf8) == "corrupt")
    }

    @Test @MainActor func abandoningStaleRecoveryErasesDraftWithoutAnotherWrite() async throws {
        let f = try ExportFixture(), draft = try f.draft()
        let client = try LocalExportClient(vault: f.vault(), failure: .afterCreate)
        let transaction = try WikiExportTransaction(journal: f.journal)
        await #expect(throws: CancellationError.self) {
            try await transaction.send(draft, acknowledgedSensitive: true, client: client, current: { f.snapshot() })
        }
        var changed = f.page
        changed.body = "Edited after the connection ended."
        await #expect(throws: WikiExportError.staleDraft) {
            try await transaction.check(client: client, current: { f.snapshot(pages: [changed]) })
        }
        try transaction.invalidate() // The app requires an explicit Abandon recovery confirmation.
        #expect(transaction.entry?.state == .invalidated)
        #expect(transaction.entry?.draft == nil)
        #expect(transaction.entry?.exportID == draft.id)
        let newDraft = try WikiExportDraft.make(selectedIDs: [changed.id], snapshot: f.snapshot(pages: [changed]))
        #expect(newDraft.id != draft.id)
        #expect(await client.writes == 1)
        #expect(try f.vault().inspect(exportID: draft.id) == draft.markdown)
    }

    @Test @MainActor func olderReceiptCannotMasqueradeAsANewFailedExport() async throws {
        let f = try ExportFixture(), original = try f.draft(), next = try f.draft()
        let client = try LocalExportClient(vault: f.vault())
        let transaction = try WikiExportTransaction(journal: f.journal)
        try await transaction.send(original, acknowledgedSensitive: true, client: client, current: { f.snapshot() })
        var changed = f.page
        changed.body += "New revision"
        await #expect(throws: WikiExportError.staleDraft) {
            try await transaction.send(next, acknowledgedSensitive: true, client: client, current: { f.snapshot(pages: [changed]) })
        }
        #expect(transaction.outcome(for: next.id) == nil)
        #expect(transaction.outcome(for: original.id)?.state == .verified)
        #expect(await client.writes == 1)
    }
}
