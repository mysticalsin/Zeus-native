import Foundation
import ZeusCore

/// One read of the local now-playing helper. The process is bounded and is killed if it is still running when the
/// setting turns off or the app quits.
enum SystemNowPlayingProcess {
    static let timeout = SystemNowPlayingLaunch.timeout
    static let maxOutputBytes = SystemNowPlayingLaunch.maxOutputBytes
    private static let lock = NSLock()
    private static var running: Process?

    static var isHelperRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running?.isRunning == true
    }

    static func read() -> String? {
        stop()
        guard let script = scriptPath() else { return nil }
        let result = run(SystemNowPlayingLaunch.executable, [script], timeout: timeout, maxOutputBytes: maxOutputBytes)
        guard result.status == 0 else { return nil }
        return result.output
    }

    /// Runs one helper and keeps it where `stop()` can kill it. The byte cap and the timeout still apply.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval, maxOutputBytes: Int) -> BoundedSubprocess.Result {
        var launched: Process?
        let result = BoundedSubprocess.run(executable, arguments, timeout: timeout, maxOutputBytes: maxOutputBytes) { process in
            lock.lock()
            running = process
            launched = process
            lock.unlock()
        }
        lock.lock()
        if running === launched { running = nil }
        lock.unlock()
        return result
    }

    static func stop() {
        lock.lock()
        let process = running
        running = nil
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    static func scriptPath() -> String? {
        if let given = ProcessInfo.processInfo.environment["ZEUS_NOW_PLAYING_SCRIPT"],
           FileManager.default.isReadableFile(atPath: given) {
            return given
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
