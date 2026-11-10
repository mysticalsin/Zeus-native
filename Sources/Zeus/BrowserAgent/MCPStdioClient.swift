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

    private let launch: Launch
    private var process: Process?
    private var input: FileHandle?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue?, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var readTask: Task<Void, Never>?
    private let errorTail = LineTail()
    private(set) var serverInfo: ServerInfo?
    private var ended = false
    /// Notifications the server sent (logging, progress), newest last, for diagnostics.
    private(set) var notifications: [String] = []

    init(launch: Launch) { self.launch = launch }

    var isRunning: Bool { process?.isRunning == true && !ended }
    var stderrTail: String { errorTail.text }

    // MARK: Lifecycle

    /// Starts the child and completes the MCP handshake.
    @discardableResult
    func start(timeout: TimeInterval = 90) async throws -> ServerInfo {
        guard process == nil else { throw MCPClientError.launchFailed("already started") }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: launch.executable)
        child.arguments = launch.arguments
        child.environment = launch.environment
        if let directory = launch.currentDirectory { child.currentDirectoryURL = directory }
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        let tail = errorTail
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { tail.append(data) }
        }
        do { try child.run() } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw MCPClientError.launchFailed(error.localizedDescription)
        }
        process = child
        input = stdin.fileHandleForWriting
        readTask = Task { [weak self] in
            var buffer = Data()
            for await chunk in stream {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[buffer.startIndex..<newline])
                    buffer = Data(buffer[buffer.index(after: newline)...])
                    if !line.isEmpty { await self?.handle(line: line) }
                }
            }
            await self?.streamEnded()
        }

        do {
            let result = try await request("initialize", MCPCodec.initializeParams(), timeout: timeout)
            let info = ServerInfo(name: result?["serverInfo"]?["name"]?.stringValue ?? "",
                                  version: result?["serverInfo"]?["version"]?.stringValue ?? "",
                                  protocolVersion: result?["protocolVersion"]?.stringValue ?? "")
            serverInfo = info
            try write(MCPCodec.notification(method: "notifications/initialized"))
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
        failAll(MCPClientError.notRunning(errorTail.text))
        guard let child = process else { return }
        try? input?.close()
        input = nil
        for _ in 0..<40 where child.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
        if child.isRunning {
            child.terminate()
            for _ in 0..<20 where child.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
        }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        readTask?.cancel()
        readTask = nil
        process = nil
        ended = true
    }

    // MARK: Requests

    private func request(_ method: String, _ params: JSONValue?, timeout: TimeInterval) async throws -> JSONValue? {
        guard isRunning else { throw MCPClientError.notRunning(errorTail.text) }
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
                do { try write(MCPCodec.request(id: id, method: method, params: params)) } catch {
                    resolve(id, .failure(error))
                }
            }
        } onCancel: {
            Task { await self.resolve(id, .failure(CancellationError())) }
        }
    }

    private func write(_ data: Data) throws {
        guard let input, isRunning else { throw MCPClientError.notRunning(errorTail.text) }
        do { try input.write(contentsOf: data) } catch { throw MCPClientError.notRunning(errorTail.text) }
    }

    private func resolve(_ id: Int, _ result: Result<JSONValue?, Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func expire(_ id: Int, label: String, seconds: Int) {
        resolve(id, .failure(MCPClientError.timedOut(label, seconds)))
    }

    private func failAll(_ error: Error) {
        for id in Array(pending.keys) { resolve(id, .failure(error)) }
    }

    // MARK: Incoming

    private func handle(line: Data) {
        guard let message = try? MCPCodec.decode(line) else { return }
        switch message {
        case .response(let id, let result, let error):
            if let error {
                resolve(id, .failure(MCPClientError.server(code: error.code, message: error.message)))
            } else {
                resolve(id, .success(result))
            }
        case .notification(let method, _):
            notifications.append(method)
            if notifications.count > 50 { notifications.removeFirst(notifications.count - 50) }
        case .request(let id, let method, _):
            // Only ping is answered; anything else gets "method not found" so the server isn't left waiting.
            if method == "ping" {
                try? write(MCPCodec.response(id: id))
            } else {
                var object: [String: JSONValue] = ["jsonrpc": .string("2.0"), "id": id]
                object["error"] = .object(["code": .number(-32_601), "message": .string("not supported")])
                if let data = try? JSONEncoder().encode(JSONValue.object(object)) { try? write(data + Data([0x0A])) }
            }
        }
    }

    private func streamEnded() {
        ended = true
        failAll(MCPClientError.notRunning(errorTail.text))
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
