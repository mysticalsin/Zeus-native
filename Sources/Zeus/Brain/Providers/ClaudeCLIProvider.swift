import Foundation
import ZeusCore

/// Runs `claude -p` headless with stream-json in and out. Your claude.ai login, settings and MCP
/// servers (toto-brain, rea, …) load exactly as in your terminal. ZEUS_INTERNAL=1 keeps these
/// calls out of the notch's agent list.
final class ClaudeCLIProvider: BrainProvider, @unchecked Sendable {
    enum ProviderError: LocalizedError {
        case notInstalled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled: "I can't find the claude command line tool."
            case .failed(let detail): detail
            }
        }
    }

    let id: ProviderID = .claudeCLI
    let capabilities: ProviderCapabilities = [.images, .streaming, .mcp]

    private let lock = NSLock()
    private var running: [UUID: Process] = [:]

    private var executable: String? {
        CLILocator.tools.first { $0.name == "claude" }.flatMap(CLILocator.locate)
    }

    func healthCheck() async -> ProviderHealth {
        guard let path = executable else { return .notInstalled }
        return .ready(version: await CLILocator.version(at: path))
    }

    func cancel(turn: UUID) async {
        PersistentClaudeSession.shared.cancel(turn: turn)
        let process = lock.withLock { running.removeValue(forKey: turn) }
        if let process, process.isRunning { process.interrupt() }
    }

    func send(_ request: BrainRequest) -> AsyncThrowingStream<BrainEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let path = executable else {
                continuation.finish(throwing: ProviderError.notInstalled)
                return
            }

            // Only the fixed persona rides in argv (visible to `ps`); remembered facts, screen and
            // agent context in the rest of the system prompt go in on stdin.
            let split = Self.splitSystemPrompt(request.systemPrompt, base: ZeusPrompt.system)
            let voice = request.firstTextBudget != nil
            let arguments = Self.launchArguments(base: split.argument, deep: request.deep, voice: voice)
            // A spoken turn reuses a lean `claude` process that is already running (started on the talk
            // key, or by the previous turn), so the turn does not pay process start. Anything else
            // (chat, routines, a busy or dead session) takes the one-shot path below.
            if voice, let runner = PersistentClaudeSession.shared.runner(deep: request.deep, executable: path, arguments: arguments),
               runner.begin(turn: request.turn, message: Self.userMessage(for: request, context: split.context),
                            continuation: continuation, firstByteBudget: request.firstTextBudget ?? 8) {
                VoiceLog.log("brain", "engine=claude persistent=yes turns=\(runner.turnsServed)")
                continuation.onTermination = { termination in
                    if case .cancelled = termination { runner.cancel(turn: request.turn) }
                }
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = CLILocator.searchDirectories.joined(separator: ":")
            environment["ZEUS_INTERNAL"] = "1"
            process.environment = environment

            let runDirectory = ZeusPaths.runDirectory(turn: request.turn)
            try? FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
            process.currentDirectoryURL = runDirectory

            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            let parser = StreamJSONParser(continuation: continuation)
            let state = CLIRunState()
            let errorTail = BoundedTail()
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    state.mark(output: true)
                    parser.consume(data)
                }
            }
            // Drained while it runs (only a bounded tail is kept) so a chatty claude never blocks on stderr.
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil; return }
                errorTail.append(data)
            }
            // No deadline used to apply: stop a claude that is silent for 90 s at the start or 120 s mid-stream.
            CLIEngineProvider.watch(process, state: state, firstByte: request.firstTextBudget ?? 90) {
                parser.fail("Claude gave no answer in time")
            }

            process.terminationHandler = { [weak self] finished in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                parser.consume(stdout.fileHandleForReading.readDataToEndOfFile())
                errorTail.append(stderr.fileHandleForReading.readDataToEndOfFile())
                self?.forget(turn: request.turn)
                try? FileManager.default.removeItem(at: runDirectory)
                if state.timedOut {
                    parser.fail("Claude gave no answer in time")
                } else {
                    parser.finish(status: finished.terminationStatus, signalled: finished.terminationReason == .uncaughtSignal, stderr: errorTail.text)
                }
            }

            continuation.onTermination = { [weak self] termination in
                if case .cancelled = termination, process.isRunning { process.interrupt() }
                self?.forget(turn: request.turn)
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: ProviderError.failed("Couldn't start claude: \(error.localizedDescription)"))
                return
            }
            lock.lock()
            running[request.turn] = process
            lock.unlock()

            let message = Self.userMessage(for: request, context: split.context)
            StdinFeeder.feed(message + Data([0x0A]), to: stdin.fileHandleForWriting)
        }
    }

    /// The full argv of one launch. The same list starts a one-shot process and a persistent one.
    static func launchArguments(base: String, deep: Bool, voice: Bool) -> [String] {
        [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--system-prompt", base,
        ] + ModelCap.arguments(for: .claude, tier: deep ? .deep : .fast)
          + (deep ? ["--effort", "medium"] : [])
          + leanArguments(voice: voice)
    }

    /// Flags for a launch. A spoken turn runs `--safe-mode`: no hooks, plugins, skills, CLAUDE.md or MCP
    /// servers and no tools (login and model selection still work). The owner's setup loaded SessionStart
    /// hooks and claude.ai connectors on every call, and a 1-line prompt took over 45 s with no output.
    /// Measured here with Claude Code 2.1.322 and Haiku: first streamed text in about 1.4 s. Other jobs
    /// (chat, routines) keep the person's full setup, minus MCP servers when the CLI supports that.
    static func leanArguments(voice: Bool) -> [String] {
        if voice, ClaudeFlags.supportsSafeMode {
            return ["--safe-mode", "--strict-mcp-config", "--tools", "", "--no-session-persistence"]
        }
        return ClaudeFlags.enabled ? ["--strict-mcp-config"] : []
    }

    /// The part of the system prompt that may go in argv, and the rest (personal context) that
    /// must not. A prompt that doesn't start with `base` is treated as all context.
    static func splitSystemPrompt(_ full: String, base: String) -> (argument: String, context: String) {
        if full.hasPrefix(base) {
            return (base, String(full.dropFirst(base.count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (base, full)
    }

    private func forget(turn: UUID) {
        lock.lock()
        running.removeValue(forKey: turn)
        lock.unlock()
    }

    /// One stream-json user message: the context text plus every screenshot as a base64 image block.
    static func userMessage(for request: BrainRequest, context: String = "") -> Data {
        var content: [JSONValue] = []
        if !context.isEmpty {
            content.append(.object(["type": .string("text"), "text": .string("Standing context for this turn:\n" + context)]))
        }
        content.append(.object(["type": .string("text"), "text": .string(ZeusPrompt.userText(for: request))]))
        for shot in request.screenshots {
            content.append(.object([
                "type": .string("image"),
                "source": .object([
                    "type": .string("base64"),
                    "media_type": .string("image/jpeg"),
                    "data": .string(shot.jpegData.base64EncodedString()),
                ]),
            ]))
        }
        let message: JSONValue = .object([
            "type": .string("user"),
            "message": .object(["role": .string("user"), "content": .array(content)]),
        ])
        return (try? JSONEncoder().encode(message)) ?? Data()
    }
}

/// Turns claude's stream-json lines into BrainEvents.
final class StreamJSONParser: @unchecked Sendable {
    private let continuation: AsyncThrowingStream<BrainEvent, Error>.Continuation
    private let lock = NSLock()
    private var buffer = Data()
    private var sawText = false
    private var resultError: String?
    private var done = false

    init(continuation: AsyncThrowingStream<BrainEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer[buffer.startIndex..<newline])
            buffer = Data(buffer[buffer.index(after: newline)...])
        }
        lock.unlock()
        lines.forEach(handle)
    }

    func handle(_ line: Data) {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: line) else { return }
        switch value["type"]?.stringValue {
        case "stream_event":
            let event = value["event"]
            if event?["type"]?.stringValue == "content_block_delta",
               event?["delta"]?["type"]?.stringValue == "text_delta",
               let text = event?["delta"]?["text"]?.stringValue {
                lock.lock(); sawText = true; lock.unlock()
                continuation.yield(.textDelta(text))
            } else if event?["type"]?.stringValue == "content_block_start",
                      event?["content_block"]?["type"]?.stringValue == "tool_use",
                      let name = event?["content_block"]?["name"]?.stringValue {
                continuation.yield(.progress(name))
            }
        case "result":
            if value["is_error"] == .bool(true) {
                lock.lock()
                resultError = value["result"]?.stringValue ?? "Claude returned an error."
                lock.unlock()
            }
        default:
            break
        }
    }

    func finish(status: Int32, signalled: Bool = false, stderr: String) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        let error = resultError
        let hadText = sawText
        lock.unlock()

        if let error {
            continuation.finish(throwing: ClaudeCLIProvider.ProviderError.failed(error))
        } else if signalled || status != 0 {
            // An abnormal exit is a failure even with partial text (which stays visible, now marked
            // incomplete). The banner comes first in stderr; the real error is the last "error" line.
            let line = CLIEngineProvider.errorLine(stderr)
            let detail = line.isEmpty ? (signalled ? "Claude was stopped before it finished" : "exit status \(status)") : line
            continuation.finish(throwing: ClaudeCLIProvider.ProviderError.failed(hadText ? "\(detail) (the answer is incomplete)" : detail))
        } else {
            continuation.yield(.done(nil))
            continuation.finish()
        }
    }

    /// Ends the stream with an error (a stalled run that was stopped), whatever text arrived.
    func fail(_ message: String) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        lock.unlock()
        continuation.finish(throwing: ClaudeCLIProvider.ProviderError.failed(message))
    }
}

/// Writes a prompt to a CLI's stdin off the caller's thread, then closes it. A CLI that exits
/// before reading (the pipe breaks) is not an error here: its exit status reports the failure.
/// SIGPIPE is ignored once so a broken pipe is an error return, never a process kill.
enum StdinFeeder {
    static let ignoreSIGPIPE: Void = { signal(SIGPIPE, SIG_IGN) }()

    static func feed(_ data: Data, to handle: FileHandle) {
        _ = ignoreSIGPIPE
        DispatchQueue.global(qos: .userInitiated).async {
            do { try handle.write(contentsOf: data) } catch {}
            try? handle.close()
        }
    }
}

/// Cached `claude --help` check. Warmed at launch so a voice turn does not wait on it.
enum ClaudeFlags {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: Bool?
    nonisolated(unsafe) private static var cachedSafeMode: Bool?

    static func warm() {
        Task.detached { _ = enabled }
    }

    static var enabled: Bool {
        if let cached = lock.withLock({ cached }) { return cached }
        let value = probe()
        return lock.withLock { cached = value.strictMCP; cachedSafeMode = value.safeMode; return value.strictMCP }
    }

    /// `claude --help` lists `--safe-mode` (Claude Code 2.1.x). Read off the same cached probe.
    static var supportsSafeMode: Bool {
        _ = enabled
        return lock.withLock { cachedSafeMode ?? false }
    }

    private static func probe() -> (strictMCP: Bool, safeMode: Bool) {
        let process = Process()
        // A GUI app's PATH has no ~/.local/bin, so `env claude` failed here and the probe wrongly said
        // "no --strict-mcp-config": every claude.ai connector then loaded on each voice turn.
        guard let path = CLILocator.tools.first(where: { $0.name == "claude" }).flatMap(CLILocator.locate) else { return (false, false) }
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--help"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = CLILocator.searchDirectories.joined(separator: ":")
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (false, false) }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return (false, false)
        }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (ClaudeLaunch.supportsStrictMCP(text), ClaudeLaunch.supportsSafeMode(text))
    }
}
