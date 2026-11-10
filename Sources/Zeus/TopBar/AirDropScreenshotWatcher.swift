import CoreServices
import Foundation
import ZeusCore

/// Event-driven directory watcher (using macOS FSEvents with file events; no polling)
/// for AirDrop arrivals in `~/Downloads` and screenshots in the screenshot destination directory.
final class AirDropScreenshotWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "zeus.intake.watcher", qos: .utility)
    private let lock = NSLock()
    private var knownDownloads: Set<String> = []
    private var knownScreenshots: Set<String> = []
    private var isInitialized = false

    private let onAirDrop: @MainActor (URL) -> Void
    private let onScreenshot: @MainActor (URL) -> Void

    init?(
        watchDownloads: Bool,
        watchScreenshots: Bool,
        onAirDrop: @escaping @MainActor (URL) -> Void,
        onScreenshot: @escaping @MainActor (URL) -> Void
    ) {
        self.onAirDrop = onAirDrop
        self.onScreenshot = onScreenshot

        var paths: [String] = []
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let screenshotURL = ScreenshotDetector.location()

        if watchDownloads && FileManager.default.fileExists(atPath: downloadsURL.path) {
            paths.append(downloadsURL.path)
            if let files = try? FileManager.default.contentsOfDirectory(atPath: downloadsURL.path) {
                knownDownloads = Set(files)
            }
        }

        if watchScreenshots && FileManager.default.fileExists(atPath: screenshotURL.path) {
            if !paths.contains(screenshotURL.path) {
                paths.append(screenshotURL.path)
            }
            if let files = try? FileManager.default.contentsOfDirectory(atPath: screenshotURL.path) {
                knownScreenshots = Set(files)
            }
        }

        guard !paths.isEmpty else { return nil }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, count, paths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<AirDropScreenshotWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            var changedPaths: [(path: String, flags: UInt32)] = []
            for i in 0..<count {
                if i < list.count {
                    changedPaths.append((list[i], eventFlags[i]))
                }
            }
            watcher.handleEvents(changedPaths)
        }

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.15,
            flags
        ) else { return nil }

        self.stream = stream
        isInitialized = true
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

    private func handleEvents(_ events: [(path: String, flags: UInt32)]) {
        lock.lock()
        defer { lock.unlock() }

        for (path, flags) in events {
            let url = URL(fileURLWithPath: path)
            let fileName = url.lastPathComponent
            guard !fileName.hasPrefix(".") else { continue }

            // Ensure the item exists
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { continue }

            let isCreatedOrModified = (flags & UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemRenamed)) != 0
            guard isCreatedOrModified else { continue }

            // Check if AirDrop in Downloads
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            if url.deletingLastPathComponent().path == downloadsURL.path {
                if !knownDownloads.contains(fileName) {
                    knownDownloads.insert(fileName)
                    if QuarantineParser.isAirDropFile(at: url) {
                        DispatchQueue.main.async { [onAirDrop] in
                            onAirDrop(url)
                        }
                    }
                }
            }

            // Check if Screenshot
            let screenshotDir = ScreenshotDetector.location().path
            if url.deletingLastPathComponent().path == screenshotDir {
                if !knownScreenshots.contains(fileName) {
                    knownScreenshots.insert(fileName)
                    if ScreenshotDetector.isScreenshot(url: url) {
                        DispatchQueue.main.async { [onScreenshot] in
                            onScreenshot(url)
                        }
                    }
                }
            }
        }
    }
}
