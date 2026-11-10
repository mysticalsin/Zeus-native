import Foundation
import ZeusCore

/// Laya on this Mac. Target: in-process ONNX Runtime with no Python (gap logged in
/// teardown/laya.md). Until that port lands, ZEUS manages a local `laya-serve` helper bound to
/// 127.0.0.1: started only on first use, stopped after five idle minutes, never at launch, and
/// skipped in Low Power Mode or when the Mac runs hot.
final class LayaHelper: DecisionProvider, @unchecked Sendable {
    static let shared = LayaHelper()
    let source = Decision.Source.laya
    static let port = 8765
    private let lock = NSLock()
    private var process: Process?
    private var idleTimer: DispatchSourceTimer?
    private lazy var residency = ModelResidency(hooks: .init(load: { [weak self] m in if m == .laya { self?.start() } },
                                                             unload: { [weak self] m in if m == .laya { self?.stop() } }))
    private let client = SystemOneClient(source: .laya, endpoint: SystemOneClient.layaEndpoint(port: LayaHelper.port), key: nil, timeout: 2)

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zeus-dev/laya") }
    static var serveBinary: URL { home.appendingPathComponent("venv/bin/laya-serve") }
    var installed: Bool { FileManager.default.isExecutableFile(atPath: Self.serveBinary.path) }
    var running: Bool { lock.lock(); defer { lock.unlock() }; return process?.isRunning == true }

    func decide(_ request: SystemOneRequest) async throws -> Decision {
        guard installed else { throw DecisionError.unavailable("laya not installed") }
        residency.use(.laya)
        scheduleIdleSweep()
        var lastError: Error = DecisionError.unavailable("laya")
        for attempt in 0..<40 {   // first use waits for the checkpoint to load, at most about 20 s
            do { return try await client.decide(request) } catch { lastError = error }
            if attempt == 0 && !running { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        throw lastError
    }

    private func start() {
        lock.lock(); defer { lock.unlock() }
        guard process?.isRunning != true else { return }
        let p = Process()
        p.executableURL = Self.serveBinary
        var env = ProcessInfo.processInfo.environment
        env["LAYA_HOST"] = "127.0.0.1"
        env["LAYA_PORT"] = String(Self.port)
        env["LAYA_MODELS"] = "multilingual"
        env["LAYA_DEFAULT_MODEL"] = "multilingual"
        env["LAYA_MAX_LOADED"] = "1"
        env["LAYA_THREADS"] = "4"
        env["LAYA_LOG_LEVEL"] = "warning"
        env["HF_HUB_CACHE"] = Self.home.appendingPathComponent("hf").path
        env["HF_HUB_OFFLINE"] = "1"
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.qualityOfService = .userInitiated
        try? p.run()
        process = p
    }

    private func stop() {
        lock.lock(); defer { lock.unlock() }
        process?.terminate()
        process = nil
    }

    /// One one-shot timer at the next possible unload time; no polling.
    private func scheduleIdleSweep() {
        guard let due = residency.nextSweep else { return }
        idleTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + max(1, due.timeIntervalSinceNow), leeway: .seconds(5))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.residency.sweep()
            if self.residency.resident != nil { self.scheduleIdleSweep() }
        }
        t.resume()
        idleTimer = t
    }

    /// Called on quit so the helper never outlives ZEUS.
    func shutdown() { stop() }
}
