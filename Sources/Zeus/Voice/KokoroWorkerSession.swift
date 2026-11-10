import Foundation

/// Keeps one Kokoro-onnx Python worker alive for the app session.
final class KokoroWorkerSession: @unchecked Sendable {
    static let shared = KokoroWorkerSession()

    private let lock = NSLock()
    private var process: Process?
    private var stdin: FileHandle?
    private var restarts: [(Date, Int)] = []
    private let maxRestarts = 3
    private let restartWindow: TimeInterval = 10 * 60

    private init() {}

    /// Loads the worker and renders a dot so the first spoken answer skips cold start.
    func prewarm(voice: String, speed: Double) async {
        guard KokoroWorker.isSetUp() else { return }
        if let url = await render(".", voice: voice, speed: speed) {
            try? FileManager.default.removeItem(at: url)
            VoiceLog.log("kokoro", "prewarm=ok voice=\(voice)")
        }
    }

    func render(_ text: String, voice: String, speed: Double) async -> URL? {
        guard KokoroWorker.isSetUp() else { return nil }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-kokoro-\(UUID().uuidString).wav")
        let line = KokoroWorker.Line(text: text, voice: voice, speed: speed, out: out.path)
        return await Task.detached { [weak self] in
            guard let self else { return nil }
            guard let payload = try? KokoroWorker.encodeLine(line) else { return nil }
            guard self.ensureProcess() else { return nil }
            guard self.write(payload) else { return nil }
            let deadline = Date().addingTimeInterval(120)
            while Date() < deadline {
                if FileManager.default.fileExists(atPath: out.path) { return out }
                try? await Task.sleep(for: .milliseconds(40))
            }
            return nil
        }.value
    }

    private func ensureProcess() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let process, process.isRunning { return true }
        let dir = KokoroWorker.modelDir()
        let python = KokoroWorker.pythonExecutable()
        guard KokoroWorker.kokoroOnnxImportWorks(python: python) else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = KokoroWorker.argv(python: python, modelDir: dir)
        let pipe = Pipe()
        proc.standardInput = pipe
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            noteRestartFailure()
            return false
        }
        process = proc
        stdin = pipe.fileHandleForWriting
        return true
    }

    private func write(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let stdin else { return false }
        do {
            try stdin.write(contentsOf: data)
            return true
        } catch {
            terminateLocked()
            return false
        }
    }

    private func noteRestartFailure() {
        let now = Date()
        restarts.append((now, 1))
        restarts.removeAll { now.timeIntervalSince($0.0) > restartWindow }
        let count = restarts.reduce(0) { $0 + $1.1 }
        if count >= maxRestarts { return }
    }

    private func terminateLocked() {
        stdin?.closeFile()
        stdin = nil
        process?.terminate()
        process = nil
    }
}
