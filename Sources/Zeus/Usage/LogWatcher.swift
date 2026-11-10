import CoreServices
import Foundation

/// FSEvents on the agents' log folders: collects the .jsonl files that changed so the usage
/// refresh stats only those instead of walking 1,000+ files every minute. Coalesced by the
/// kernel (5 s latency), delivered on a utility queue, never on the main thread.
final class LogWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "zeus.usage.watch", qos: .utility)
    private let lock = NSLock()
    private var pending: Set<URL> = []
    /// Set when FSEvents dropped events or a root was replaced: the next scan must walk.
    private var mustWalk = false

    init?(roots: [URL], latency: TimeInterval = 5) {
        let paths = roots.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return nil }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, count, paths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<LogWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            var urls: [URL] = []
            var walk = false
            for i in 0..<count {
                let f = eventFlags[i]
                if f & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
                              | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped) != 0 { walk = true }
                if i < list.count, list[i].hasSuffix(".jsonl") { urls.append(URL(fileURLWithPath: list[i])) }
            }
            watcher.note(urls, walk: walk)
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func note(_ urls: [URL], walk: Bool) {
        lock.lock(); defer { lock.unlock() }
        pending.formUnion(urls)
        if walk { mustWalk = true }
    }

    /// What changed since the last call; `walk` is true when events were lost.
    func drain() -> (changed: Set<URL>, walk: Bool) {
        lock.lock(); defer { lock.unlock() }
        let out = (pending, mustWalk)
        pending = []
        mustWalk = false
        return out
    }
}
