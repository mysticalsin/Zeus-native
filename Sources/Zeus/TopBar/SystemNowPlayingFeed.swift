import Foundation
import ZeusCore

/// One read of the local now-playing helper. The process is bounded and is killed if it is still running when the
/// setting turns off or the app quits.
enum SystemNowPlayingProcess {
    static let timeout = SystemNowPlayingLaunch.timeout
    static let maxOutputBytes = SystemNowPlayingLaunch.maxOutputBytes
    /// The helper process, guarded by its own lock. The stored reference is immutable, so this is not shared mutable global state.
    private static let running = RunningHelper()

    private final class RunningHelper: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        var isRunning: Bool { lock.withLock { process?.isRunning == true } }
        func store(_ process: Process) { lock.withLock { self.process = process } }
        func clear(_ process: Process) { lock.withLock { if self.process === process { self.process = nil } } }
        func take() -> Process? { lock.withLock { let current = process; process = nil; return current } }
    }

    static var isHelperRunning: Bool { running.isRunning }

    static func read() -> String? {
        stop()
        guard let script = scriptPath() else { return nil }
        let caller = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/zeus-now-playing").path
        let result = run(SystemNowPlayingLaunch.executable, [script, caller], timeout: timeout, maxOutputBytes: maxOutputBytes)
        guard result.status == 0 else { return nil }
        return result.output
    }

    /// Runs one helper and keeps it where `stop()` can kill it. The byte cap and the timeout still apply.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval, maxOutputBytes: Int) -> BoundedSubprocess.Result {
        var launched: Process?
        let result = BoundedSubprocess.run(executable, arguments, timeout: timeout, maxOutputBytes: maxOutputBytes) { process in
            running.store(process)
            launched = process
        }
        if let launched { running.clear(launched) }
        return result
    }

    static func stop() {
        guard let process = running.take(), process.isRunning else { return }
        process.terminate()
    }

    static func scriptPath() -> String? {
        if let given = ProcessInfo.processInfo.environment["ZEUS_NOW_PLAYING_SCRIPT"],
           FileManager.default.isReadableFile(atPath: given) {
            return given
        }
        if let bundled = Bundle.main.url(forResource: "now-playing", withExtension: "pl"),
           FileManager.default.isReadableFile(atPath: bundled.path) {
            return bundled.path
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("scripts/now-playing.pl")
        if FileManager.default.isReadableFile(atPath: cwd.path) { return cwd.path }
        return nil
    }
}

/// Polls the helper while the setting is on and reports the line to the hub as the system source.
@MainActor
final class SystemNowPlayingFeed {
    private let hub: NowPlayingHub
    private let read: () -> String?
    private var timer: Timer?

    init(hub: NowPlayingHub, read: @escaping () -> String? = { SystemNowPlayingProcess.read() }) {
        self.hub = hub
        self.read = read
    }

    func setEnabled(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        SystemNowPlayingProcess.stop()
        guard on else {
            hub.update(.system, nil, announce: false)
            return
        }
        poll()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() { setEnabled(false) }

    private func poll() {
        guard let text = read(), let line = SystemNowPlayingAdapter.parse(text) else {
            hub.update(.system, nil, announce: false)
            return
        }
        let item = NowPlaying(source: .system, title: line.title, artist: line.artist, album: line.album,
                              isPlaying: line.playing, duration: line.duration, position: line.position)
        hub.update(.system, item, announce: false)
    }
}
