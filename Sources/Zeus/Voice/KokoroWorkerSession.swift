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
    private static let launchLock = NSLock()
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
         temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.configuration = configuration
        self.requestTimeout = requestTimeout
        self.idleTimeout = idleTimeout
        self.temporaryDirectory = temporaryDirectory
    }

    deinit {
        startup?.cancel(); idle?.cancel()
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
        guard !closed, !Task.isCancelled, pending == nil, closing == nil,
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
        failPending()
        stopWorker()
        if let closing { await closing.value }
    }

    private func start(_ launch: Launch?) async {
        startup = nil
        guard !closed, pending != nil, closing == nil else { return }
        guard let launch else { failPending(); return }
        do {
            let (process, stdin, stdout) = try Self.launchLock.withLock {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launch.executable)
                process.arguments = launch.arguments
                let stdin = Pipe(), stdout = Pipe()
                for handle in [stdin.fileHandleForReading, stdin.fileHandleForWriting,
                               stdout.fileHandleForReading, stdout.fileHandleForWriting] {
                    guard fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0 else { throw CocoaError(.fileWriteUnknown) }
                }
                process.standardInput = stdin
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice
                try process.run()
                try? stdin.fileHandleForReading.close()
                try? stdout.fileHandleForWriting.close()
                return (process, stdin, stdout)
            }
            child = process
            defer { try? stdin.fileHandleForWriting.close(); try? stdout.fileHandleForReading.close() }
            input = try MCPPipeIO(handle: stdin.fileHandleForWriting, name: "kokoro-input")
            output = try MCPPipeIO(handle: stdout.fileHandleForReading, name: "kokoro-output")
            generation = UUID()
            let current = generation
            output?.read(consume: { [weak self] data in await self?.consume(data, generation: current) ?? false },
                         ended: { [weak self] in await self?.ended(current) })
            if let id = pending?.id { await send(id) }
        } catch { failPending(); stopWorker() }
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
        guard process.isRunning else { return true }
        process.terminate()
        for _ in 0..<25 where process.isRunning { try? await Task.sleep(for: .milliseconds(10)) }
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        for _ in 0..<100 where process.isRunning { try? await Task.sleep(for: .milliseconds(10)) }
        return !process.isRunning
    }
}
