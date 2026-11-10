import Foundation
import Testing
import ZeusCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
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

    @Test func blockedPipeWriteKeepsActorResponsiveAndDeadlineClosesTransport() async throws {
        let transport = Self.fixture(afterHandshake: "exec /bin/sleep 30")
        try await transport.start(timeout: 2)
        let request = Task { try await transport.callTool("blocked", arguments: ["body": .string(String(repeating: "x", count: 2 * 1024 * 1024))], timeout: 1) }
        try await Self.waitForPendingRequest(transport)
        try await Task.sleep(for: .milliseconds(40))
        let began = ContinuousClock.now
        _ = await transport.isRunning
        #expect(began.duration(to: .now) < .milliseconds(250), "A full child stdin must not block the MCP actor")
        await #expect(throws: (any Error).self) { try await request.value }
        #expect(await transport.isRunning == false)
        await transport.close()
    }

    @Test func cancellingBlockedWriteStopsTheTransportWithoutWaitingForPipeSpace() async throws {
        let transport = Self.fixture(afterHandshake: "exec /bin/sleep 30")
        try await transport.start(timeout: 2)
        let request = Task { try await transport.callTool("blocked", arguments: ["body": .string(String(repeating: "x", count: 2 * 1024 * 1024))], timeout: 20) }
        try await Self.waitForPendingRequest(transport)
        try await Task.sleep(for: .milliseconds(40))
        let began = ContinuousClock.now
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(began.duration(to: .now) < .milliseconds(500))
        // Shutdown begins on cancellation even though the child never drains stdin.
        #expect(await transport.isRunning == false)
        await transport.close()
    }

    @Test func oversizedUnterminatedOutputIsRejectedBeforeThePeerCanGrowTheBuffer() async throws {
        let transport = Self.fixture(afterHandshake: """
        IFS= read -r request || exit 1
        /bin/dd if=/dev/zero bs=65536 count=129 2>/dev/null
        """)
        try await transport.start(timeout: 2)
        do {
            _ = try await transport.callTool("oversized", arguments: [:], timeout: 3)
            Issue.record("Oversized stream was accepted")
        } catch let error as MCPClientError {
            #expect(error == .badResponse("message exceeds the transport limit"))
        }
        await transport.close()
        #expect(await transport.isRunning == false)
    }

    @Test func partialFinalMessageIsRejectedAndChildIsClosed() async throws {
        let transport = Self.fixture(afterHandshake: """
        IFS= read -r request || exit 1
        printf '%s' '{"jsonrpc":"2.0","id":2,"result":'
        """)
        try await transport.start(timeout: 2)
        do {
            _ = try await transport.callTool("truncated", arguments: [:], timeout: 2)
            Issue.record("Partial JSON response was accepted")
        } catch let error as MCPClientError {
            #expect(error == .badResponse("incomplete message at end of stream"))
        }
        await transport.close()
        #expect(await transport.isRunning == false)
    }

    @Test func concurrentHelpersDoNotKeepEachOthersOutputOpen() async throws {
        let sleeping = Self.fixture(afterHandshake: "exec /bin/sleep 30")
        let truncated = Self.fixture(afterHandshake: """
        IFS= read -r request || exit 1
        printf '%s' '{"jsonrpc":"2.0","id":2,"result":'
        """)
        do {
            async let first = sleeping.start(timeout: 3)
            async let second = truncated.start(timeout: 3)
            _ = try await (first, second)
            do {
                _ = try await truncated.callTool("truncated", arguments: [:], timeout: 2)
                Issue.record("Partial JSON response was accepted")
            } catch let error as MCPClientError {
                #expect(error == .badResponse("incomplete message at end of stream"))
            }
            #expect(await sleeping.isRunning)
            await truncated.close()
            await sleeping.close()
        } catch {
            await truncated.close()
            await sleeping.close()
            throw error
        }
    }

    @Test func malformedCompleteMessagesCloseTheTransportWithoutWaitingForTimeout() async throws {
        for line in ["not JSON", #"{"jsonrpc":"2.0","id":1e100,"result":{}}"#] {
            let transport = Self.fixture(afterHandshake: """
            IFS= read -r request || exit 1
            printf '%s\n' '\(line)'
            while IFS= read -r request; do :; done
            """)
            try await transport.start(timeout: 2)
            let began = ContinuousClock.now
            do {
                _ = try await transport.callTool("malformed", arguments: [:], timeout: 10)
                Issue.record("Malformed complete response was accepted")
            } catch let error as MCPClientError {
                #expect(error == .badResponse("invalid JSON-RPC message"))
            }
            #expect(began.duration(to: .now) < .seconds(2))
            #expect(await transport.isRunning == false)
            await transport.close()
        }
    }

    @Test func notificationBurstIsDrainedWithBoundedDiagnosticsAndExactReply() async throws {
        // One arbitrarily large grapheme cluster must still consume at most 256 wire bytes.
        let method = "n" + String(repeating: "\u{0301}", count: 1_000)
        let transport = Self.fixture(afterHandshake: """
        IFS= read -r request || exit 1
        i=0
        while [ "$i" -lt 200 ]; do
          printf '%s\n' '{"jsonrpc":"2.0","method":"\(method)"}'
          i=$((i + 1))
        done
        printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"complete"}]}}'
        while IFS= read -r request; do :; done
        """)
        do {
            try await transport.start(timeout: 2)
            let result = try await transport.callTool("burst", arguments: [:], timeout: 3)
            #expect(result.text == "complete")
            let diagnostics = await transport.notifications
            #expect(diagnostics.count == 50)
            #expect(diagnostics.allSatisfy { $0 == String(decoding: method.utf8.prefix(256), as: UTF8.self) })
            #expect(diagnostics.allSatisfy { $0.utf8.count <= 258 })
            await transport.close()
        } catch { await transport.close(); throw error }
    }

    @Test func writingToAClosedPipeThrowsWithoutRaisingSIGPIPE() async throws {
        // Open both pipe ends with atomic CLOEXEC. A bare Foundation Pipe can
        // leave a reader in a concurrently launched child, invalidating the
        // closed-reader premise even after this process closes its copy.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-closed-pipe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("stream").path
        try #require(mkfifo(path, 0o600) == 0)
        let readFD = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        try #require(readFD >= 0)
        let reader = FileHandle(fileDescriptor: readFD, closeOnDealloc: true)
        defer { try? reader.close() }
        let writeFD = open(path, O_WRONLY | O_NONBLOCK | O_CLOEXEC)
        try #require(writeFD >= 0)
        let handle = FileHandle(fileDescriptor: writeFD, closeOnDealloc: true)
        defer { try? handle.close() }
        try #require(unlink(path) == 0) // No subsequent opener can introduce a reader.
        let writer = try MCPPipeIO(handle: handle, name: "closed-pipe-fixture")
        defer { writer.stop() }
        let control = Data("fixture".utf8)
        try await writer.write(control, deadline: ProcessInfo.processInfo.systemUptime + 0.2)
        let received = try reader.read(upToCount: control.count)
        try #require(received == control, "The same writer must transfer bytes before its reader closes")
        try reader.close()
        // A concurrent spawn may briefly hold CLOEXEC descriptors before exec.
        // Establish that all readers are gone without retrying a failed write.
        let readyDeadline = ProcessInfo.processInfo.systemUptime + 0.2
        var noReaders = false
        repeat {
            var descriptor = pollfd(fd: writeFD, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&descriptor, 1, 0)
            if ready < 0, errno == EINTR { continue }
            try #require(ready >= 0 && descriptor.revents & Int16(POLLNVAL) == 0)
            noReaders = descriptor.revents & Int16(POLLERR | POLLHUP) != 0
            if noReaders { break }
            try await Task.sleep(for: .milliseconds(1))
        } while ProcessInfo.processInfo.systemUptime < readyDeadline
        try #require(noReaders, "The kernel must confirm this pipe has no readers")
        try handle.close()
        do {
            try await writer.write(control, deadline: ProcessInfo.processInfo.systemUptime + 0.2)
            Issue.record("A write succeeded after the only reader closed")
        } catch MCPPipeIO.Failure.unavailable {
            // Keep the actual unavailable-stream result: timeout/stopped errors
            // must not make this closed-pipe regression pass.
        }
    }

    @Test func slowConsumerReceivesOneChunkAndStopCancelsASuspendedReader() async throws {
        let pipe = Pipe()
        let reader = try MCPPipeIO(handle: pipe.fileHandleForReading, name: "backpressure-reader-fixture")
        let writer = try MCPPipeIO(handle: pipe.fileHandleForWriting, name: "backpressure-writer-fixture")
        try pipe.fileHandleForReading.close()
        try pipe.fileHandleForWriting.close()
        defer { reader.stop(); writer.stop() }
        let probe = ReadProbe()
        reader.read(consume: { await probe.consume($0) }, ended: { await probe.end() })
        let writing = Task {
            try await writer.write(Data(repeating: 0x78, count: 1024 * 1024),
                                   deadline: ProcessInfo.processInfo.systemUptime + 2)
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await probe.chunks == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(40))
        #expect(await probe.chunks == 1)
        #expect(await probe.bytes <= 16_384)
        reader.stop() // Cancellation must also close a currently suspended DispatchSource.
        await #expect(throws: (any Error).self) { try await writing.value }
        let endDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await probe.endCount == 0, ContinuousClock.now < endDeadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await probe.endCount == 1)
        await probe.release()
    }

    private actor ReadProbe {
        private(set) var chunks = 0
        private(set) var bytes = 0
        private(set) var endCount = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func consume(_ data: Data) async -> Bool {
            chunks += 1
            bytes += data.count
            await withCheckedContinuation { waiters.append($0) }
            return true
        }
        func end() { endCount += 1 }
        func release() {
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }

    private static func waitForPendingRequest(_ transport: MCPStdioClient) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await transport.pendingRequestCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await transport.pendingRequestCount == 1)
    }

    /// Shell builtins and fixed local fixture commands only. No provider, vault, network,
    /// capture service, installed app, user preference or permission API is accessed.
    private static func fixture(afterHandshake: String) -> MCPStdioClient {
        let script = """
        IFS= read -r initialize || exit 1
        printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","serverInfo":{"name":"fixture","version":"1"}}}'
        IFS= read -r initialized || exit 1
        \(afterHandshake)
        """
        return MCPStdioClient(launch: .init(executable: "/bin/sh", arguments: ["-c", script], environment: [:], currentDirectory: nil))
    }

}
