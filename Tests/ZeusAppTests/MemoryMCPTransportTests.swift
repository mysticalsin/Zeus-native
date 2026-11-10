import Foundation
import Testing
import ZeusCore
#if ZEUS_PORTABLE_MCP
@testable import MCPTransportValidation
#else
@testable import Zeus
#endif

@Suite("Memory MCP process transport")
struct MemoryMCPTransportTests {
    @Test func bundledHelperCompletesInteractiveMCPRoundTrip() async throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #if ZEUS_PORTABLE_MCP
        let executable = package.appendingPathComponent(".build/debug/zeus-memory-helper")
        let prefix: [String] = []
        #else
        let executable = package.appendingPathComponent(".build/debug/zeus-cli")
        let prefix = ["memory-mcp"]
        #endif
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-mcp-process-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = BrainConnection(source: BrainSource(kind: .markdown, name: "Disposable", path: root.path), access: .readWrite)
        let page = WikiPage(id: "selected", title: "Unicode body", body: String(repeating: "Résumé 🦉\n", count: 8_000), updatedAt: Date())
        let snapshot = WikiExportSnapshot(pages: [page], connection: connection, availableMeetingIDs: [],
                                          forgottenMeetingIDs: [], sourceTitles: [:], settingsReadable: true)
        let draft = try WikiExportDraft.make(selectedIDs: [page.id], snapshot: snapshot)
        let transport = MCPStdioClient(launch: .init(executable: executable.path,
            arguments: prefix + ["--vault", root.path, "--inbox", connection.inboxFolder, "--identity", draft.destination.rootIdentity],
            environment: [:], currentDirectory: nil))
        do {
            let info = try await transport.start(timeout: 3)
            #expect(info.name == WikiExportMCP.serverName)
            #expect(info.protocolVersion == MCPCodec.protocolVersion)
            try await WikiExportMCP.discover(transport)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
            #expect(try await WikiExportMCP.inspect(draft, client: transport) == .missing)
            try await WikiExportMCP.create(draft, client: transport)
            #expect(try await WikiExportMCP.inspect(draft, client: transport)
                == .verified(relativePath: draft.destination.relativePath(exportID: draft.id), bytes: draft.markdown.utf8.count))
            // The real helper, not an in-memory fake, persisted exactly the previewed Unicode bytes.
            let note = root.appendingPathComponent(draft.destination.relativePath(exportID: draft.id))
            #expect(try Data(contentsOf: note) == Data(draft.markdown.utf8))
            await transport.close()
            #expect(await transport.isRunning == false)
        } catch { await transport.close(); throw error }
    }

    @Test func handshakeTimeoutClosesTheChildProcess() async throws {
        let transport = MCPStdioClient(launch: .init(executable: "/bin/sleep", arguments: ["30"], environment: [:], currentDirectory: nil))
        await #expect(throws: (any Error).self) { try await transport.start(timeout: 0.05) }
        #expect(await transport.isRunning == false)
    }

    @Test func cancelledHandshakeClosesTheChildProcess() async throws {
        let transport = MCPStdioClient(launch: .init(executable: "/bin/sleep", arguments: ["30"], environment: [:], currentDirectory: nil))
        let task = Task { try await transport.start(timeout: 20) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.isRunning == false)
    }
}
