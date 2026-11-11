import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// One resident local voice worker, one admitted request, and no queued synthesis.
/// Cancellation invalidates the entire worker: partially written requests are never replayed.
actor KokoroWorkerSession {
    struct Launch: Sendable {
        let executable: String
        let arguments: [String]
    }
    static let shared = KokoroWorkerSession()
    static let maximumTextBytes = 16_384
    static let maximumReplyBytes = 16_384
    static let maximumWAVBytes = 64 * 1024 * 1024
    enum LaunchPhase: String, Sendable { case queued, began, returned, failed, skipped }
    private static let defaultLaunchQueue = DispatchQueue(label: "zeus.kokoro.launch", qos: .utility)
    private let launchQueue: DispatchQueue
    private let launchProcess: @Sendable (Process) throws -> Void
    private let launchObserver: @Sendable (LaunchPhase) -> Void
    private let configuration: @Sendable () -> Launch?
    private let requestTimeout: TimeInterval
    private let idleTimeout: TimeInterval
    private let temporaryDirectory: URL
    private var child: Process?
    private var input: MCPPipeIO?
    private var output: MCPPipeIO?
    private var buffer = Data()
    private var generation = UUID()
    private var pending: Pending?
    private var startup: Task<Void, Never>?
    private var launching: Task<Void, Never>?
    private var closing: Task<Bool, Never>?
    private var idle: Task<Void, Never>?
    private var closed = false

    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    private struct Pending {
        let id: UUID
        let cancellation: Cancellation
        let directory: URL
        let output: URL
        let message: Data
        let deadline: TimeInterval
        let continuation: CheckedContinuation<URL?, Never>
        let timer: Task<Void, Never>
    }
    private struct Reply: Decodable {
        let id: String
        let out: String
        let ok: Bool
    }

    init(configuration: @escaping @Sendable () -> Launch? = {
        guard KokoroWorker.modelFilesPresent() else { return nil }
        let python = KokoroWorker.pythonExecutable()
        guard KokoroWorker.kokoroOnnxImportWorks(python: python) else { return nil }
        return Launch(executable: python, arguments: KokoroWorker.argv(python: python, modelDir: KokoroWorker.modelDir()))
    }, requestTimeout: TimeInterval = 120, idleTimeout: TimeInterval = 120,
         temporaryDirectory: URL = FileManager.default.temporaryDirectory,
         launchQueue: DispatchQueue? = nil,
         launchProcess: @escaping @Sendable (Process) throws -> Void = { try $0.run() },
         launchObserver: @escaping @Sendable (LaunchPhase) -> Void = { _ in }) {
        self.configuration = configuration
        self.requestTimeout = requestTimeout
        self.idleTimeout = idleTimeout
        self.temporaryDirectory = temporaryDirectory
        self.launchQueue = launchQueue ?? Self.defaultLaunchQueue
        self.launchProcess = launchProcess
        self.launchObserver = launchObserver
    }

    deinit {
        startup?.cancel(); idle?.cancel()
        pending?.cancellation.cancel()
        input?.stop(); output?.stop()
        pending?.timer.cancel()
        pending?.continuation.resume(returning: nil)
        if let directory = pending?.directory { try? FileManager.default.removeItem(at: directory) }
        if let child { Task { await Self.finishChild(child) } }
    }

    var isRunning: Bool { child?.isRunning == true }
    var pendingRequestCount: Int { pending == nil ? 0 : 1 }

    func prewarm(voice: String, speed: Double) async {
        if let url = await render(".", voice: voice, speed: speed) {
            try? FileManager.default.removeItem(at: url)
            VoiceLog.log("kokoro", "prewarm=ok voice=\(voice)")
        }
    }

    func render(_ text: String, voice: String, speed: Double) async -> URL? {
        guard !closed, !Task.isCancelled, pending == nil, closing == nil, launching == nil,
              !text.isEmpty, text.utf8.count <= Self.maximumTextBytes,
              !voice.isEmpty, voice.utf8.count <= 128,
              speed.isFinite, speed >= 0.25, speed <= 4,
              requestTimeout.isFinite, requestTimeout > 0, requestTimeout <= 300,
              idleTimeout.isFinite, idleTimeout > 0 else { return nil }
        let id = UUID()
        let cancellation = Cancellation()
        let rendered: URL? = await withTaskCancellationHandler {
            guard !Task.isCancelled else { return nil }
            return await withCheckedContinuation { continuation in
                guard !cancellation.isCancelled else { continuation.resume(returning: nil); return }
                let directory = temporaryDirectory.appendingPathComponent("zeus-kokoro-work-\(id.uuidString)", isDirectory: true)
                let out = directory.appendingPathComponent("audio.wav")
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                            attributes: [.posixPermissions: 0o700])
                    let message = try KokoroWorker.encodeLine(.init(id: id.uuidString, text: text, voice: voice, speed: speed, out: out.path))
                    let deadline = ProcessInfo.processInfo.systemUptime + requestTimeout
                    let timer = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(self?.requestTimeout ?? 0)) } catch { return }
                        await self?.cancel(id)
                    }
                    pending = Pending(id: id, cancellation: cancellation, directory: directory, output: out, message: message,
                                      deadline: deadline, continuation: continuation, timer: timer)
                    idle?.cancel(); idle = nil
                    if isRunning, input != nil { Task { await self.send(id) } }
                    else if startup == nil {
                        // One setup probe can outlive a cancelled request, but no second probe or
                        // unbounded queue is created. The probe itself uses bounded helper execution.
                        startup = Task { [weak self, configuration] in
                            let launch = await Task.detached(operation: configuration).value
                            await self?.start(launch)
                        }
                    }
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    continuation.resume(returning: nil)
                }
            }
        } onCancel: { cancellation.cancel(); Task { await self.cancel(id) } }
        if Task.isCancelled {
            if let rendered { try? FileManager.default.removeItem(at: rendered) }
            return nil
        }
        return rendered
    }

    func close() async {
        closed = true
        pending?.cancellation.cancel()
        failPending()
        stopWorker()
        // Process.run is not interruptible. Join its handoff and any late child cleanup.
        if let launching { await launching.value }
        if let closing { await closing.value }
    }

    /// A launch result has one owner until its descriptors are duplicated or closed.
    private final class Spawned: @unchecked Sendable {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()

        init() {
            // A failed bounded cleanup must not discard a still-running Process.
            // Break this deliberate retention only after Foundation observes termination.
            process.terminationHandler = { [process] _ in process.terminationHandler = nil }
        }

        func closeChildEnds() {
            try? stdin.fileHandleForReading.close()
            try? stdout.fileHandleForWriting.close()
        }

        func closeParentEnds() {
            try? stdin.fileHandleForWriting.close()
            try? stdout.fileHandleForReading.close()
        }

        deinit { closeChildEnds(); closeParentEnds() }
    }

    private enum LaunchOutcome: Sendable {
        case skipped
        case finished(Spawned, succeeded: Bool)
    }

    private static func spawn(_ launch: Launch, queue: DispatchQueue,
                              run: @escaping @Sendable (Process) throws -> Void,
                              observe: @escaping @Sendable (LaunchPhase) -> Void,
                              cancellation: Cancellation, deadline: TimeInterval) async -> LaunchOutcome {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !cancellation.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else {
                    observe(.skipped)
                    continuation.resume(returning: .skipped)
                    return
                }
                let spawned = Spawned()
                var succeeded = false
                do {
                    spawned.process.executableURL = URL(fileURLWithPath: launch.executable)
                    spawned.process.arguments = launch.arguments
                    for handle in [spawned.stdin.fileHandleForReading, spawned.stdin.fileHandleForWriting,
                                   spawned.stdout.fileHandleForReading, spawned.stdout.fileHandleForWriting] {
                        guard fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0 else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                    }
                    spawned.process.standardInput = spawned.stdin
                    spawned.process.standardOutput = spawned.stdout
                    spawned.process.standardError = FileHandle.nullDevice
                    guard !cancellation.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else {
                        spawned.process.terminationHandler = nil
                        observe(.skipped)
                        continuation.resume(returning: .skipped)
                        return
                    }
                    observe(.began)
                    try run(spawned.process)
                    succeeded = true
                    observe(.returned)
                } catch {
                    observe(.failed)
                }
                if !spawned.process.isRunning { spawned.process.terminationHandler = nil }
                spawned.closeChildEnds()
                continuation.resume(returning: .finished(spawned, succeeded: succeeded))
            }
        }
    }

    private func start(_ launch: Launch?) async {
        startup = nil
        guard !closed, let request = pending, closing == nil, launching == nil else { return }
        guard let launch else { failPending(); return }
        guard !request.cancellation.isCancelled, ProcessInfo.processInfo.systemUptime < request.deadline else {
            cancel(request.id); return
        }
        let id = request.id, cancellation = request.cancellation, deadline = request.deadline
        launchObserver(.queued)
        // The config probe can be reused during setup; a process launch cannot.
        launching = Task { [weak self, launchQueue, launchProcess, launchObserver] in
            let outcome = await Self.spawn(launch, queue: launchQueue, run: launchProcess,
                                          observe: launchObserver, cancellation: cancellation, deadline: deadline)
            if let self {
                await self.finishLaunch(outcome, id: id, cancellation: cancellation, deadline: deadline)
            } else if case .finished(let spawned, _) = outcome {
                spawned.closeParentEnds()
                _ = await Self.finishChild(spawned.process)
            }
        }
    }

    private func finishLaunch(_ outcome: LaunchOutcome, id: UUID,
                              cancellation: Cancellation, deadline: TimeInterval) async {
        defer { launching = nil }
        guard case .finished(let spawned, let succeeded) = outcome else {
            if pending?.id == id { cancel(id) }
            return
        }
        child = spawned.process
        defer { spawned.closeParentEnds() }
        guard succeeded, !closed, pending?.id == id, !cancellation.isCancelled,
              ProcessInfo.processInfo.systemUptime < deadline else {
            if pending?.id == id { failPending() }
            spawned.closeParentEnds()
            stopWorker()
            if let closing { await closing.value }
            return
        }
        do {
            input = try MCPPipeIO(handle: spawned.stdin.fileHandleForWriting, name: "kokoro-input")
            output = try MCPPipeIO(handle: spawned.stdout.fileHandleForReading, name: "kokoro-output")
            generation = UUID()
            let current = generation
            output?.read(consume: { [weak self] data in await self?.consume(data, generation: current) ?? false },
                         ended: { [weak self] in await self?.ended(current) })
            // Clear launch ownership before request I/O can publish a fast reply.
            Task { await self.send(id) }
        } catch {
            if pending?.id == id { failPending() }
            spawned.closeParentEnds()
            stopWorker()
            if let closing { await closing.value }
        }
    }

    private func send(_ id: UUID) async {
        guard let request = pending, request.id == id, let input else { return }
        do { try await input.write(request.message, deadline: request.deadline) }
        catch { cancel(id) }
    }

    private func consume(_ data: Data, generation current: UUID) -> Bool {
        guard current == generation, !closed else { return false }
        for byte in data {
            if byte == 10 {
                let line = buffer; buffer.removeAll(keepingCapacity: true)
                guard let response = try? JSONDecoder().decode(Reply.self, from: line),
                      let request = pending, response.id == request.id.uuidString,
                      response.out == request.output.path, response.ok,
                      ProcessInfo.processInfo.systemUptime < request.deadline,
                      let published = publish(request) else {
                    failPending(); stopWorker(); return false
                }
                guard !request.cancellation.isCancelled, ProcessInfo.processInfo.systemUptime < request.deadline else {
                    try? FileManager.default.removeItem(at: published)
                    failPending(); stopWorker(); return false
                }
                request.timer.cancel()
                pending = nil
                request.continuation.resume(returning: published)
                armIdleShutdown()
            } else {
                guard buffer.count < Self.maximumReplyBytes else { failPending(); stopWorker(); return false }
                buffer.append(byte)
            }
        }
        return current == generation
    }

    private func publish(_ request: Pending) -> URL? {
        let target = temporaryDirectory.appendingPathComponent("zeus-kokoro-\(request.id.uuidString).wav")
        guard KokoroWAVArtifact.publish(request.output, to: target, maximumBytes: Self.maximumWAVBytes, shouldStop: {
            request.cancellation.isCancelled || ProcessInfo.processInfo.systemUptime >= request.deadline
        }) else { return nil }
        try? FileManager.default.removeItem(at: request.directory)
        return target
    }

    private func cancel(_ id: UUID) {
        guard pending?.id == id else { return }
        pending?.cancellation.cancel()
        failPending()
        stopWorker()
    }

    private func failPending() {
        guard let request = pending else { return }
        pending = nil
        request.timer.cancel()
        try? FileManager.default.removeItem(at: request.directory)
        request.continuation.resume(returning: nil)
    }

    private func ended(_ current: UUID) {
        guard current == generation else { return }
        failPending(); stopWorker()
    }

    private func stopWorker() {
        generation = UUID()
        idle?.cancel(); idle = nil
        input?.stop(); output?.stop()
        input = nil; output = nil; buffer.removeAll(keepingCapacity: false)
        guard let process = child else { return }
        child = nil
        let cleanup = Task { await Self.finishChild(process) }
        closing = cleanup
        Task { [weak self] in
            let exited = await cleanup.value
            await self?.finishedClosing(exited)
        }
    }

    private func finishedClosing(_ exited: Bool) {
        if !exited { closed = true } // Never spawn a replacement while the previous child may still exist.
        closing = nil
    }

    private func armIdleShutdown() {
        idle?.cancel()
        let current = generation
        idle = Task { [weak self, idleTimeout] in
            do { try await Task.sleep(for: .seconds(idleTimeout)) } catch { return }
            await self?.expireIdle(current)
        }
    }

    private func expireIdle(_ current: UUID) {
        guard current == generation, pending == nil, !Task.isCancelled else { return }
        stopWorker()
    }

    private static func finishChild(_ process: Process) async -> Bool {
        guard process.isRunning else {
            // Once exit is observed this cannot wait for a running child; on
            // corelibs Foundation it also releases the retained run-loop source.
            if process.processIdentifier > 0 { process.waitUntilExit() }
            process.terminationHandler = nil
            return true
        }
        process.terminate()
        for _ in 0..<25 where process.isRunning { try? await Task.sleep(for: .milliseconds(10)) }
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        for _ in 0..<100 where process.isRunning { try? await Task.sleep(for: .milliseconds(10)) }
        let exited = !process.isRunning
        if exited {
            process.waitUntilExit()
            process.terminationHandler = nil
        }
        return exited
    }
}
