import Foundation
import ZeusCore

/// What the browser backend needs from an MCP server. The real one is `MCPStdioClient`; tests pass
/// a fake that replays the recorded browser-use responses.
protocol MCPToolCalling: Sendable {
    func callTool(_ name: String, arguments: [String: JSONValue], timeout: TimeInterval) async throws -> MCPToolResult
    /// Ends the server cleanly.
    func close() async
}

enum MCPClientError: Error, LocalizedError, Equatable {
    case launchFailed(String)
    case notRunning(String)
    case timedOut(String, Int)
    case server(code: Int, message: String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let why): "The separate browser didn't start: \(why)"
        case .notRunning(let tail): tail.isEmpty ? "The separate browser stopped." : "The separate browser stopped: \(tail)"
        case .timedOut(let what, let seconds): "The separate browser didn't answer \(what) within \(seconds) seconds."
        case .server(_, let message): "The separate browser said: \(message)"
        case .badResponse(let what): "The separate browser sent something unexpected (\(what))."
        }
    }
}

/// A minimal MCP client over stdio: newline-delimited JSON-RPC 2.0 to a child process. It does the
/// handshake (initialize, then the initialized notification), tools/list and tools/call, answers
/// ping, keeps the tail of stderr for error messages, times every request out, and ends the child
/// cleanly (close stdin, wait, then terminate, then kill).
actor MCPStdioClient: MCPToolCalling {
    struct Launch: Sendable {
        var executable: String
        var arguments: [String]
        var environment: [String: String]
        var currentDirectory: URL?
    }

    struct ServerInfo: Equatable, Sendable {
        let name: String
        let version: String
        let protocolVersion: String
    }

    // Foundation Pipe creation and CLOEXEC flagging are not one atomic operation.
    // Serialize that short spawn window across MCP helpers, never request I/O.
    private static let launchLock = NSLock()
    private let launch: Launch
    private var process: Process?
    private var input: MCPPipeIO?
    private var output: MCPPipeIO?
    private var errorOutput: MCPPipeIO?
    private var buffer = Data()
    /// Large enough for the bounded 512 KiB Memory export plus JSON escaping and
    /// ordinary browser results. A hostile peer cannot enlarge this allocation.
    static let maximumMessageBytes = 8 * 1024 * 1024
    static let maximumPendingRequests = 16
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue?, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private let errorTail = LineTail()
    private(set) var serverInfo: ServerInfo?
    private var ended = false
    private var closing: Task<Void, Never>?
    /// Notifications the server sent (logging, progress), newest last, for diagnostics.
    private(set) var notifications: [String] = []

    init(launch: Launch) { self.launch = launch }

    deinit {
        input?.stop()
        output?.stop()
        errorOutput?.stop()
        if let child = process { Task { await Self.finishChild(child) } }
    }

    var isRunning: Bool { process?.isRunning == true && !ended }
    var stderrTail: String { errorTail.text }
    var pendingRequestCount: Int { pending.count }

    // MARK: Lifecycle

    /// Starts the child and completes the MCP handshake.
    @discardableResult
    func start(timeout: TimeInterval = 90) async throws -> ServerInfo {
        guard process == nil, !ended else { throw MCPClientError.launchFailed("already started") }
        let (child, stdin, stdout, stderr) = try Self.launchLock.withLock {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: launch.executable)
            child.arguments = launch.arguments
            child.environment = launch.environment
            if let directory = launch.currentDirectory { child.currentDirectoryURL = directory }
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            // Do not let a concurrently launched helper inherit another transport's pipe ends.
            for handle in [stdin.fileHandleForReading, stdin.fileHandleForWriting,
                           stdout.fileHandleForReading, stdout.fileHandleForWriting,
                           stderr.fileHandleForReading, stderr.fileHandleForWriting] {
                guard fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0 else {
                    throw MCPClientError.launchFailed("could not isolate child pipes")
                }
            }
            child.standardInput = stdin
            child.standardOutput = stdout
            child.standardError = stderr

            do { try child.run() } catch {
                throw MCPClientError.launchFailed(error.localizedDescription)
            }
            // The child owns its duplicated standard descriptors after run(). Close all
            // parent copies of the child-facing ends even if Process retains the Pipe.
            try? stdin.fileHandleForReading.close()
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
            return (child, stdin, stdout, stderr)
        }
        process = child

        do {
            input = try MCPPipeIO(handle: stdin.fileHandleForWriting, name: "stdin")
            output = try MCPPipeIO(handle: stdout.fileHandleForReading, name: "stdout")
            errorOutput = try MCPPipeIO(handle: stderr.fileHandleForReading, name: "stderr")
            try stderr.fileHandleForReading.close()
            let tail = errorTail
            errorOutput?.read(consume: { data in tail.append(data); return true }, ended: {})
            try stdin.fileHandleForWriting.close()
            try stdout.fileHandleForReading.close()
            output?.read(consume: { [weak self] data in await self?.consume(data) ?? false },
                         ended: { [weak self] in await self?.streamEnded() })
            let result = try await request("initialize", MCPCodec.initializeParams(), timeout: timeout)
            let info = ServerInfo(name: result?["serverInfo"]?["name"]?.stringValue ?? "",
                                  version: result?["serverInfo"]?["version"]?.stringValue ?? "",
                                  protocolVersion: result?["protocolVersion"]?.stringValue ?? "")
            serverInfo = info
            try await write(MCPCodec.notification(method: "notifications/initialized"), timeout: timeout)
            return info
        } catch {
            await close()
            throw error
        }
    }

    func listTools(timeout: TimeInterval = 20) async throws -> [MCPToolInfo] {
        MCPToolInfo.parse(try await request("tools/list", .object([:]), timeout: timeout))
    }

    func callTool(_ name: String, arguments: [String: JSONValue], timeout: TimeInterval = 60) async throws -> MCPToolResult {
        let result = try await request("tools/call", MCPCodec.callParams(name: name, arguments: arguments), timeout: timeout)
        guard let tool = MCPToolResult(result: result) else { throw MCPClientError.badResponse("\(name) had no content") }
        return tool
    }

    /// Closes stdin (the server's cue to stop), waits a few seconds, then terminates and finally kills.
    func close() async {
        stopIO()
        failAll(MCPClientError.notRunning(errorTail.text))
        if let closing { await closing.value; return }
        guard let child = process else { return }
        let cleanup = Task { await Self.finishChild(child) }
        closing = cleanup
        await cleanup.value
        process = nil
    }

    private func stopIO() {
        ended = true
        input?.stop()
        output?.stop()
        input = nil
        output = nil
        buffer.removeAll(keepingCapacity: false)
        errorOutput?.stop()
        errorOutput = nil
    }

    private static func finishChild(_ child: Process) async {
        for _ in 0..<40 where child.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
        if child.isRunning {
            child.terminate()
            for _ in 0..<20 where child.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
        }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
    }

    // MARK: Requests

    private func request(_ method: String, _ params: JSONValue?, timeout: TimeInterval) async throws -> JSONValue? {
        try Task.checkCancellation()
        guard isRunning else { throw MCPClientError.notRunning(errorTail.text) }
        guard timeout.isFinite, timeout > 0, timeout <= 3_600,
              pending.count < Self.maximumPendingRequests else { throw MCPClientError.badResponse("invalid timeout or too many pending requests") }
        let id = nextID
        nextID += 1
        let label = method == "tools/call" ? (params?["name"]?.stringValue ?? method) : method
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue?, Error>) in
                pending[id] = continuation
                timeouts[id] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    if !Task.isCancelled { await self?.expire(id, label: label, seconds: Int(timeout)) }
                }
                Task {
                    do { try await write(MCPCodec.request(id: id, method: method, params: params), timeout: timeout) }
                    catch {
                        stopIO()
                        resolve(id, .failure(error))
                        await close() // A partial JSON line must never be followed by a new request.
                    }
                }
            }
        } onCancel: {
            Task {
                await self.cancel(id)
            }
        }
    }

    private func cancel(_ id: Int) async {
        guard pending[id] != nil else { return }
        stopIO() // Publish shutdown before resuming the cancelled caller.
        resolve(id, .failure(CancellationError()))
        await close()
    }

    private func write(_ data: Data, timeout: TimeInterval = 10) async throws {
        guard let input, isRunning else { throw MCPClientError.notRunning(errorTail.text) }
        guard data.count <= Self.maximumMessageBytes else { throw MCPClientError.badResponse("message exceeds the transport limit") }
        do { try await input.write(data, deadline: ProcessInfo.processInfo.systemUptime + timeout) }
        catch { throw MCPClientError.notRunning(errorTail.text) }
    }

    private func resolve(_ id: Int, _ result: Result<JSONValue?, Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func expire(_ id: Int, label: String, seconds: Int) {
        guard pending[id] != nil else { return }
        stopIO()
        resolve(id, .failure(MCPClientError.timedOut(label, seconds)))
        Task { await close() }
    }

    private func failAll(_ error: Error) {
        for id in Array(pending.keys) { resolve(id, .failure(error)) }
    }

    // MARK: Incoming

    private func consume(_ chunk: Data) async -> Bool {
        guard !ended else { return false }
        // Process each segment before appending the next, so a chunk containing
        // many short messages does not consume the per-message budget together.
        var start = chunk.startIndex
        while start < chunk.endIndex {
            let newline = chunk[start...].firstIndex(of: 0x0A)
            let end = newline ?? chunk.endIndex
            guard end - start <= Self.maximumMessageBytes - buffer.count else {
                stopIO()
                failAll(MCPClientError.badResponse("message exceeds the transport limit"))
                await close()
                return false
            }
            buffer.append(contentsOf: chunk[start..<end])
            guard let newline else { break }
            let line = buffer
            buffer = Data()
            if !line.isEmpty { await handle(line: line) }
            guard !ended else { return false }
            start = newline + 1
        }
        return true
    }

    private func handle(line: Data) async {
        let message: MCPIncoming
        do { message = try MCPCodec.decode(line) }
        catch {
            stopIO()
            failAll(MCPClientError.badResponse("invalid JSON-RPC message"))
            await close()
            return
        }
        switch message {
        case .response(let id, let result, let error):
            if let error {
                resolve(id, .failure(MCPClientError.server(code: error.code, message: error.message)))
            } else {
                resolve(id, .success(result))
            }
        case .notification(let method, _):
            notifications.append(String(decoding: method.utf8.prefix(256), as: UTF8.self))
            if notifications.count > 50 { notifications.removeFirst(notifications.count - 50) }
        case .request(let id, let method, _):
            // Only ping is answered; anything else gets "method not found" so the server isn't left waiting.
            if method == "ping" {
                do { try await write(MCPCodec.response(id: id)) } catch { await close() }
            } else {
                var object: [String: JSONValue] = ["jsonrpc": .string("2.0"), "id": id]
                object["error"] = .object(["code": .number(-32_601), "message": .string("not supported")])
                if let data = try? JSONEncoder().encode(JSONValue.object(object)) {
                    do { try await write(data + Data([0x0A])) } catch { await close() }
                }
            }
        }
    }

    private func streamEnded() async {
        guard !ended else { return }
        let error = buffer.isEmpty ? MCPClientError.notRunning(errorTail.text)
            : MCPClientError.badResponse("incomplete message at end of stream")
        stopIO()
        failAll(error)
        await close()
    }
}

/// The last few KB of a child's stderr, readable from any thread.
final class LineTail: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let limit = 4_096

    func append(_ data: Data) {
        lock.withLock {
            buffer.append(data)
            if buffer.count > limit { buffer = Data(buffer.suffix(limit)) }
        }
    }

    /// The last non-empty line.
    var text: String {
        lock.withLock {
            String(decoding: buffer, as: UTF8.self).split(whereSeparator: \.isNewline).last
                .map { String($0.trimmingCharacters(in: .whitespaces).prefix(200)) } ?? ""
        }
    }
}
