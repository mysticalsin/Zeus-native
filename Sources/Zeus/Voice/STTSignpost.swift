import os

/// Signposts for the speech-to-text stages. Debug builds only, so a release app does not
/// emit them. Names are stage ids. Transcript text is never a signpost argument.
enum STTSignpost {
    private static let log = OSLog(subsystem: "app.zeus.mac", category: "stt")

    static func event(_ name: StaticString) {
        #if DEBUG
        os_signpost(.event, log: log, name: name)
        #endif
    }
}

/// Lets a recognition callback and its give-up timer complete a caller exactly once.
final class STTOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        lock.unlock()
        body()
    }
}
