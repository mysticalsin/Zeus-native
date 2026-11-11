import Foundation
import ZeusCore

/// One lean `claude -p --input-format stream-json` process kept running between spoken turns, so a turn
/// does not pay process start (the one-shot path took about 1.4 s to the first streamed text, most of it
/// start-up). Flags come from `ClaudeCLIProvider.launchArguments`, the same list the one-shot path uses
/// (`--safe-mode`: no hooks, plugins, MCP servers or tools). The process is started on the talk key,
/// never at launch, and is replaced by `PersistentCLIPolicy` after a few turns or when its flags change.
final class PersistentClaudeRunner: @unchecked Sendable {
    let launchKey: String
    let startedAt = Date()

    private let process = Process()
    private let stdinHandle: FileHandle
    private let runDirectory: URL
    private let lock = NSLock()
    private var buffer = Data()
    private var active: (turn: UUID, parser: StreamJSONParser)?
    /// Results still to come from turns that were cancelled while the CLI was generating them.
    private var ghostResults = 0
    private var served = 0
    private var dead = false
    private var turnSawOutput = false
    private let errorTail = BoundedTail()

    var turnsServed: Int { lock.withLock { served } }
    var isAlive: Bool { lock.withLock { !dead } && process.isRunning }
    var isBusy: Bool { lock.withLock { active != nil || ghostResults > 0 } }

    init?(launchKey: String, executable: String, arguments: [String]) {
        self.launchKey = launchKey
        runDirectory = ZeusPaths.runDirectory(turn: UUID())
        try? FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = CLILocator.searchDirectories.joined(separator: ":")
        environment["ZEUS_INTERNAL"] = "1"
        process.environment = environment
        process.currentDirectoryURL = runDirectory
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdinHandle = stdin.fileHandleForWriting
        _ = StdinFeeder.ignoreSIGPIPE
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            self?.consume(data)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            self?.errorTail.append(data)
        }
        process.terminationHandler = { [weak self] finished in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            self?.terminated(status: finished.terminationStatus, signalled: finished.terminationReason == .uncaughtSignal)
        }
        do { try process.run() } catch {
            try? FileManager.default.removeItem(at: runDirectory)
            return nil
        }
    }

    /// Hands one turn's message to the running process. False when the process is gone or already serving a turn.
    func begin(turn: UUID, message: Data, continuation: AsyncThrowingStream<BrainEvent, Error>.Continuation,
               firstByteBudget: TimeInterval) -> Bool {
        let parser = StreamJSONParser(continuation: continuation)
        lock.lock()
        guard !dead, active == nil else { lock.unlock(); return false }
        active = (turn, parser)
        served += 1
        turnSawOutput = false
        lock.unlock()
        let payload = message + Data([0x0A])
        let handle = stdinHandle
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do { try handle.write(contentsOf: payload) } catch { self?.kill(reason: "Claude could not be reached") }
        }
        Task.detached { [weak self] in
            try? await Task.sleep(for: .seconds(firstByteBudget))
            guard let self else { return }
            let stalled = self.lock.withLock { self.active?.turn == turn && !self.turnSawOutput }
            if stalled { self.kill(reason: "Claude gave no answer in time") }
        }
        return true
    }

    /// A turn that lost the race or was replaced. Its output is dropped; the process stays up for the next turn.
    func cancel(turn: UUID) {
        let parser: StreamJSONParser? = lock.withLock {
            guard active?.turn == turn, let parser = active?.parser else { return nil }
            active = nil
            ghostResults += 1
            return parser
        }
        parser?.fail("Cancelled")
    }

    /// Stops the process now (a barge-in, or a stall). The next turn starts a fresh one.
    func kill(reason: String) {
        let parser: StreamJSONParser? = lock.withLock {
            dead = true
            let parser = active?.parser
            active = nil
            return parser
        }
        parser?.fail(reason)
        if process.isRunning { process.terminate() }
    }

    private func consume(_ data: Data) {
        var lines: [Data] = []
        lock.lock()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(Data(buffer[buffer.startIndex..<newline]))
            buffer = Data(buffer[buffer.index(after: newline)...])
        }
        lock.unlock()
        lines.forEach(route)
    }

    private func route(_ line: Data) {
        let isResult = (try? JSONDecoder().decode(JSONValue.self, from: line))?["type"]?.stringValue == "result"
        var parser: StreamJSONParser?
        lock.lock()
        if ghostResults > 0 {
            if isResult { ghostResults -= 1 }
            lock.unlock()
            return
        }
        parser = active?.parser
        if parser != nil { turnSawOutput = true }
        if isResult { active = nil }
        lock.unlock()
        parser?.handle(line)
        if isResult { parser?.finish(status: 0, stderr: "") }
    }

    private func terminated(status: Int32, signalled: Bool) {
        let parser: StreamJSONParser? = lock.withLock {
            dead = true
            let parser = active?.parser
            active = nil
            return parser
        }
        try? FileManager.default.removeItem(at: runDirectory)
        parser?.finish(status: status == 0 ? 1 : status, signalled: signalled, stderr: errorTail.text)
    }
}

/// The lean `claude` processes by tier. Owns when to start, reuse and replace them (`PersistentCLIPolicy`).
final class PersistentClaudeSession: @unchecked Sendable {
    static let shared = PersistentClaudeSession()

    private let lock = NSLock()
    private var runners: [String: PersistentClaudeRunner] = [:]

    static func launchKey(deep: Bool, arguments: [String]) -> String {
        "\(deep ? "deep" : "fast")-\(arguments.joined(separator: "\u{1}").hashValue)"
    }

    /// The process for this tier: the running one, or a new one when there is none or `PersistentCLIPolicy` says so.
    func runner(deep: Bool, executable: String, arguments: [String]) -> PersistentClaudeRunner? {
        let key = Self.launchKey(deep: deep, arguments: arguments)
        let slotName = deep ? "deep" : "fast"
        return lock.withLock {
            let existing = runners[slotName]
            let slot = existing.map {
                PersistentCLIPolicy.Slot(launchKey: $0.launchKey, turnsServed: $0.turnsServed, startedAt: $0.startedAt, alive: $0.isAlive)
            }
            if PersistentCLIPolicy.action(existing: slot, wantedKey: key, now: Date()) == .reuse, let existing { return existing }
            existing?.kill(reason: "Replaced")
            guard let fresh = PersistentClaudeRunner(launchKey: key, executable: executable, arguments: arguments) else {
                runners[slotName] = nil
                return nil
            }
            runners[slotName] = fresh
            return fresh
        }
    }

    /// Starts the fast-tier process if none is ready. Called on the talk key, off the main thread.
    func warm() {
        guard let path = CLILocator.tools.first(where: { $0.name == "claude" }).flatMap(CLILocator.locate) else { return }
        let arguments = ClaudeCLIProvider.launchArguments(base: ZeusPrompt.system, deep: false, voice: true)
        _ = runner(deep: false, executable: path, arguments: arguments)
    }

    func cancel(turn: UUID) {
        let all = lock.withLock { Array(runners.values) }
        all.forEach { $0.cancel(turn: turn) }
    }

    /// A barge-in: stop generation now in any process still working on a turn. The talk key warms a new one.
    func abortBusy() {
        let busy = lock.withLock { runners.values.filter(\.isBusy) }
        busy.forEach { $0.kill(reason: "Interrupted") }
    }
}
