import Dispatch
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Step-zero proof on a temporary folder. A file rewritten in place is seen by
/// the file source, and a replaced file is seen and that source is reopened.
/// With both sources off, the 250 ms stamp check still sees the change. A grant
/// that was on at the start ends on. A sight carries no file bytes.
///
/// Darwin watches with a file-system object source (write, extend, attribute,
/// link, rename, delete). Linux has no vnode source in this Swift, so the same
/// watch is an inotify descriptor read by a Dispatch read source.
final class StepZeroFocusWatch: @unchecked Sendable {
    enum Sight: Equatable, Sendable {
        case fileEvent
        case folderEvent
        case poll
        case watchFailed
    }

    struct Snapshot: Equatable, Sendable {
        var sights: [Sight]
        var generation: Int
        var watchedInode: UInt64?
        var running: Bool
    }

    /// The backstop reads the stamp on this interval and the bytes never.
    static let pollInterval: TimeInterval = 0.25

    /// Off, then on, when the grant started on, so the run ends on.
    /// On, then off, when it started off, so the run ends off.
    static func grantSteps(startedOn: Bool) -> [Bool] {
        startedOn ? [false, true] : [true, false]
    }

    static func inode(at url: URL) -> UInt64? {
        Stamp.read(path: url.path)?.inode
    }

    private let folder: URL
    private let fileName: String
    private let sourcesEnabled: Bool
    private let pollEnabled: Bool
    private let queue = DispatchQueue(label: "step-zero-focus-watch")
    private let lock = NSLock()
    private var sights: [Sight] = []
    private var generation = 0
    private var watchedInode: UInt64?
    private var baseline: Stamp?
    private var running = false
    private var closed = true
    private var timer: DispatchSourceTimer?
    #if canImport(Darwin)
    private var folderSource: (any DispatchSourceFileSystemObject)?
    private var fileSource: (any DispatchSourceFileSystemObject)?
    #elseif canImport(Glibc)
    private var inotifyFD: Int32 = -1
    private var folderWD: Int32 = -1
    private var fileWD: Int32 = -1
    private var reader: DispatchSourceRead?
    #endif

    init(folder: URL, fileName: String, sourcesEnabled: Bool, pollEnabled: Bool) {
        self.folder = folder
        self.fileName = fileName
        self.sourcesEnabled = sourcesEnabled
        self.pollEnabled = pollEnabled
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        guard Stamp.isDirectory(path: folder.path) else { return fail() }
        update {
            closed = false
            running = false
            sights.removeAll()
            generation = 0
            watchedInode = nil
            baseline = Stamp.read(path: fileURL.path)
        }
        if sourcesEnabled {
            #if canImport(Darwin)
            guard installDarwinFolder() else { return fail() }
            #elseif canImport(Glibc)
            guard installLinuxFolder() else { return fail() }
            #endif
        }
        update { running = true }
        if sourcesEnabled {
            refreshFile()
        }
        if pollEnabled {
            installPoll()
        }
        resumeSources()
        return true
    }

    func stop() {
        let first = update { () -> Bool in
            let wasOpen = !closed
            running = false
            closed = true
            return wasOpen
        }
        guard first else { return }
        timer?.cancel()
        timer = nil
        #if canImport(Darwin)
        fileSource?.cancel()
        fileSource = nil
        folderSource?.cancel()
        folderSource = nil
        #elseif canImport(Glibc)
        reader?.cancel()
        reader = nil
        folderWD = -1
        fileWD = -1
        inotifyFD = -1
        #endif
    }

    func snapshot() -> Snapshot {
        update { Snapshot(sights: sights, generation: generation, watchedInode: watchedInode, running: running) }
    }

    private var fileURL: URL {
        folder.appendingPathComponent(fileName)
    }

    private func fail() -> Bool {
        update {
            sights = [.watchFailed]
            running = false
            closed = true
        }
        stop()
        update {
            sights = [.watchFailed]
            running = false
        }
        return false
    }

    private func installPoll() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.pollInterval, repeating: Self.pollInterval)
        timer.setEventHandler { [weak self] in
            self?.pollTick()
        }
        self.timer = timer
    }

    private func resumeSources() {
        #if canImport(Darwin)
        folderSource?.resume()
        #elseif canImport(Glibc)
        reader?.resume()
        #endif
        timer?.resume()
    }

    private func pollTick() {
        let stamp = Stamp.read(path: fileURL.path)
        update {
            guard running, let stamp else { return }
            if let baseline {
                guard baseline != stamp else { return }
            }
            sights.append(.poll)
            baseline = stamp
        }
    }

    private func record(_ sight: Sight) {
        update {
            guard running else { return }
            sights.append(sight)
        }
    }

    private func receiveFile(gone: Bool) {
        record(.fileEvent)
        if gone {
            refreshFile()
        }
    }

    private func receiveFolder() {
        record(.folderEvent)
        refreshFile()
    }

    private func refreshFile() {
        if update({ closed || !sourcesEnabled }) { return }
        let path = fileURL.path
        let stamp = Stamp.read(path: path)
        let same = update { () -> Bool in
            guard !closed else { return true }
            return stamp != nil && stamp?.inode == watchedInode && fileInstalled
        }
        if same { return }
        #if canImport(Darwin)
        replaceDarwinFile(stamp: stamp, path: path)
        #elseif canImport(Glibc)
        replaceLinuxFile(stamp: stamp, path: path)
        #endif
    }

    private func update<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    #if canImport(Darwin)
    private var fileInstalled: Bool { fileSource != nil }

    nonisolated(unsafe) private static let eventMask: DispatchSource.FileSystemEvent = [
        .write, .extend, .attrib, .link, .rename, .delete,
    ]

    nonisolated static func folderHandler(
        source: any DispatchSourceFileSystemObject,
        watch: StepZeroFocusWatch
    ) -> @Sendable () -> Void {
        { [weak watch] in
            _ = source.data
            watch?.receiveFolder()
        }
    }

    nonisolated static func fileHandler(
        source: any DispatchSourceFileSystemObject,
        watch: StepZeroFocusWatch
    ) -> @Sendable () -> Void {
        { [weak watch] in
            let events = source.data
            let gone = events.contains(.delete) || events.contains(.rename) || events.contains(.revoke)
            watch?.receiveFile(gone: gone)
        }
    }

    private func installDarwinFolder() -> Bool {
        let fd = open(folder.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: Self.eventMask,
            queue: queue
        )
        source.setEventHandler(handler: Self.folderHandler(source: source, watch: self))
        source.setCancelHandler { close(fd) }
        folderSource = source
        return true
    }

    private func replaceDarwinFile(stamp: Stamp?, path: String) {
        let old = update { () -> (any DispatchSourceFileSystemObject)? in
            let source = fileSource
            fileSource = nil
            return source
        }
        old?.cancel()
        guard let stamp else {
            update { watchedInode = nil }
            return
        }
        if update({ closed }) { return }
        let fd = open(path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: Self.eventMask,
            queue: queue
        )
        source.setEventHandler(handler: Self.fileHandler(source: source, watch: self))
        source.setCancelHandler { close(fd) }
        source.resume()
        let dropped = update { () -> Bool in
            if closed { return true }
            fileSource = source
            watchedInode = stamp.inode
            generation += 1
            return false
        }
        if dropped {
            source.cancel()
        }
    }
    #elseif canImport(Glibc)
    private var fileInstalled: Bool { fileWD >= 0 }

    private static let fileMask = UInt32(IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_MOVE_SELF | IN_DELETE_SELF)
    private static let folderMask = UInt32(IN_MODIFY | IN_ATTRIB | IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO)
    private static let identityMask = UInt32(IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO)

    nonisolated static func readHandler(fd: Int32, watch: StepZeroFocusWatch) -> @Sendable () -> Void {
        { [weak watch] in
            watch?.drain(fd)
        }
    }

    private func installLinuxFolder() -> Bool {
        let fd = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
        guard fd >= 0 else { return false }
        let wd = inotify_add_watch(fd, folder.path, Self.folderMask)
        guard wd >= 0 else {
            close(fd)
            return false
        }
        inotifyFD = fd
        folderWD = wd
        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        reader.setEventHandler(handler: Self.readHandler(fd: fd, watch: self))
        reader.setCancelHandler { close(fd) }
        self.reader = reader
        return true
    }

    private func drain(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Int(read(fd, base, raw.count))
            }
            if count <= 0 { break }
            var offset = 0
            let fixed = MemoryLayout<inotify_event>.size
            while offset + fixed <= count {
                let event = buffer.withUnsafeBytes { raw in
                    raw.load(fromByteOffset: offset, as: inotify_event.self)
                }
                offset += fixed + Int(event.len)
                deliver(event)
            }
        }
    }

    private func deliver(_ event: inotify_event) {
        let folder = update { folderWD }
        let file = update { fileWD }
        if event.wd == folder {
            if event.mask & Self.identityMask != 0 {
                receiveFolder()
            } else {
                record(.folderEvent)
            }
        } else if event.wd == file {
            let ignored = UInt32(IN_IGNORED)
            let onlyIgnored = event.mask & ignored != 0 && event.mask & ~ignored == 0
            let gone = event.mask & UInt32(IN_DELETE_SELF | IN_MOVE_SELF | IN_IGNORED) != 0
            if onlyIgnored {
                if gone {
                    refreshFile()
                }
            } else {
                receiveFile(gone: gone)
            }
        }
    }

    private func replaceLinuxFile(stamp: Stamp?, path: String) {
        let old = update { () -> Int32 in
            let wd = fileWD
            fileWD = -1
            return wd
        }
        if old >= 0, inotifyFD >= 0 {
            _ = inotify_rm_watch(inotifyFD, old)
        }
        guard let stamp, inotifyFD >= 0 else {
            update { watchedInode = nil }
            return
        }
        if update({ closed }) { return }
        let wd = inotify_add_watch(inotifyFD, path, Self.fileMask)
        guard wd >= 0 else { return }
        let dropped = update { () -> Bool in
            if closed { return true }
            fileWD = wd
            watchedInode = stamp.inode
            generation += 1
            return false
        }
        if dropped, inotifyFD >= 0 {
            _ = inotify_rm_watch(inotifyFD, wd)
        }
    }
    #endif

    private struct Stamp: Equatable {
        var inode: UInt64
        var size: UInt64
        var modified: TimeInterval

        static func read(path: String) -> Stamp? {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
            guard let inode = attrs[.systemFileNumber] as? NSNumber else { return nil }
            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return Stamp(inode: inode.uint64Value, size: size, modified: modified)
        }

        static func isDirectory(path: String) -> Bool {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
            return (attrs[.type] as? FileAttributeType) == .typeDirectory
        }
    }
}

// Tests.

@Suite("Step zero focus watch", .serialized)
struct StepZeroFocusWatchTests {
    @Test func fileSourceSeesAnInPlaceRewrite() async throws {
        let box = try TemporaryRecords()
        defer { box.destroy() }
        try box.write("seed")
        let watch = StepZeroFocusWatch(folder: box.root, fileName: "record.json", sourcesEnabled: true, pollEnabled: false)
        #expect(watch.start() == true)
        defer { watch.stop() }
        let started = watch.snapshot()
        #expect(started.generation == 1)
        #expect(started.watchedInode != nil)
        try box.write("rewritten-in-place")
        let shot = await wait(on: watch) { $0.sights.contains(.fileEvent) }
        #expect(shot.sights.contains(.fileEvent))
        #expect(shot.generation == started.generation)
        #expect(shot.watchedInode == started.watchedInode)
        #expect(shot.watchedInode == StepZeroFocusWatch.inode(at: box.file))
        // A folder source on Darwin misses an in-place rewrite. Linux reports that rewrite on the directory watch too.
        #if os(macOS)
        #expect(shot.sights.contains(.folderEvent) == false)
        #endif
    }

    @Test func replacedFileIsSeenAndTheSourceReopens() async throws {
        let box = try TemporaryRecords()
        defer { box.destroy() }
        try box.write("original")
        let watch = StepZeroFocusWatch(folder: box.root, fileName: "record.json", sourcesEnabled: true, pollEnabled: false)
        #expect(watch.start() == true)
        defer { watch.stop() }
        let before = watch.snapshot()
        #expect(before.generation == 1)
        try box.replace(with: "replaced-file-body")
        let reopened = await wait(on: watch) { shot in
            shot.generation > before.generation && shot.watchedInode == StepZeroFocusWatch.inode(at: box.file)
        }
        #expect(reopened.generation > before.generation)
        #expect(reopened.watchedInode != before.watchedInode)
        #expect(reopened.sights.contains(.fileEvent) || reopened.sights.contains(.folderEvent))
        let fileEvents = reopened.sights.filter { $0 == .fileEvent }.count
        try box.write("reopened-source-sees-this")
        let after = await wait(on: watch) { $0.sights.filter { $0 == .fileEvent }.count > fileEvents }
        #expect(after.sights.filter { $0 == .fileEvent }.count > fileEvents)
        #expect(after.watchedInode == reopened.watchedInode)
        #expect(after.generation == reopened.generation)
    }

    @Test func pollSeesTheChangeWhenBothSourcesAreOff() async throws {
        let box = try TemporaryRecords()
        defer { box.destroy() }
        try box.write("quiet")
        let watch = StepZeroFocusWatch(folder: box.root, fileName: "record.json", sourcesEnabled: false, pollEnabled: true)
        #expect(watch.start() == true)
        defer { watch.stop() }
        #expect(StepZeroFocusWatch.pollInterval == 0.25)
        try box.write("quiet-but-the-stamp-moved")
        let shot = await wait(on: watch) { $0.sights.contains(.poll) }
        #expect(shot.sights == [.poll])
    }

    @Test func anUnchangedStampAddsNoPoll() async throws {
        let box = try TemporaryRecords()
        defer { box.destroy() }
        try box.write("still")
        let watch = StepZeroFocusWatch(folder: box.root, fileName: "record.json", sourcesEnabled: false, pollEnabled: true)
        #expect(watch.start() == true)
        defer { watch.stop() }
        try await Task.sleep(for: .milliseconds(700))
        #expect(watch.snapshot().sights.isEmpty)
        #expect(watch.snapshot().running == true)
    }

    @Test func aGrantThatWasOnAtTheStartEndsOn() {
        let steps = StepZeroFocusWatch.grantSteps(startedOn: true)
        #expect(steps == [false, true])
        #expect(steps.first == false)
        #expect(steps.last == true)
    }

    @Test func aGrantThatWasOffAtTheStartEndsOff() {
        let steps = StepZeroFocusWatch.grantSteps(startedOn: false)
        #expect(steps == [true, false])
        #expect(steps.last == false)
        #expect(steps != StepZeroFocusWatch.grantSteps(startedOn: true))
    }

    @Test func theFolderSourceRunsUntilTheFileAppears() async throws {
        let box = try TemporaryRecords()
        defer { box.destroy() }
        let watch = StepZeroFocusWatch(folder: box.root, fileName: "record.json", sourcesEnabled: true, pollEnabled: false)
        #expect(watch.start() == true)
        defer { watch.stop() }
        let started = watch.snapshot()
        #expect(started.generation == 0)
        #expect(started.watchedInode == nil)
        try box.write("born")
        let appeared = await wait(on: watch) { shot in
            shot.generation == 1 && shot.watchedInode == StepZeroFocusWatch.inode(at: box.file)
        }
        #expect(appeared.generation == 1)
        #expect(appeared.sights.contains(.folderEvent))
        #expect(appeared.watchedInode != nil)
        let fileEvents = appeared.sights.filter { $0 == .fileEvent }.count
        try box.write("born-and-then-rewritten")
        let after = await wait(on: watch) { $0.sights.filter { $0 == .fileEvent }.count > fileEvents }
        #expect(after.sights.filter { $0 == .fileEvent }.count > fileEvents)
        #expect(after.generation == 1)
    }

    @Test func aMissingFolderReportsWatchFailed() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-focus-missing-\(UUID().uuidString)", isDirectory: true)
        let watch = StepZeroFocusWatch(folder: missing, fileName: "record.json", sourcesEnabled: true, pollEnabled: false)
        #expect(watch.start() == false)
        #expect(watch.snapshot().sights == [.watchFailed])
        #expect(watch.snapshot().running == false)
        #expect(watch.snapshot().generation == 0)
    }

    @Test func stoppingDropsLaterChanges() async throws {
        let box = try TemporaryRecords()
        defer { box.destroy() }
        try box.write("before")
        let watch = StepZeroFocusWatch(folder: box.root, fileName: "record.json", sourcesEnabled: true, pollEnabled: true)
        #expect(watch.start() == true)
        defer { watch.stop() }
        try box.write("before-seen-by-the-source")
        let seen = await wait(on: watch) { $0.sights.contains(.fileEvent) }
        #expect(seen.sights.contains(.fileEvent))
        watch.stop()
        let count = watch.snapshot().sights.count
        #expect(watch.snapshot().running == false)
        try box.write("after-the-stop-this-must-stay-unseen")
        try await Task.sleep(for: .milliseconds(700))
        #expect(watch.snapshot().sights.count == count)
        #expect(watch.snapshot().running == false)
    }

    @Test func aSightKeepsNoFileBytes() async throws {
        let planted = "PlantedFocusName"
        let address = "AA:BB:CC:DD:EE:FF"
        let box = try TemporaryRecords()
        defer { box.destroy() }
        try box.write("\(planted) \(address) one")
        let watch = StepZeroFocusWatch(folder: box.root, fileName: "record.json", sourcesEnabled: false, pollEnabled: true)
        #expect(watch.start() == true)
        defer { watch.stop() }
        let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        let prefix = temp.hasSuffix("/") ? temp : temp + "/"
        #expect(box.root.resolvingSymlinksInPath().path.hasPrefix(prefix))
        try box.write("\(planted) \(address) two-longer")
        let shot = await wait(on: watch) { $0.sights.contains(.poll) }
        #expect(shot.sights.contains(.poll))
        for sight in shot.sights {
            var dumped = ""
            dump(sight, to: &dumped)
            let mirror = Mirror(reflecting: sight)
            #expect(mirror.displayStyle == .enum)
            #expect(Array(mirror.children).isEmpty)
            for text in [String(describing: sight), String(reflecting: sight), dumped] {
                #expect(text.contains(planted) == false)
                #expect(text.contains(address) == false)
            }
        }
    }
}

private func wait(
    on watch: StepZeroFocusWatch,
    for timeout: Duration = .seconds(2),
    until ready: (StepZeroFocusWatch.Snapshot) -> Bool
) async -> StepZeroFocusWatch.Snapshot {
    let clock = ContinuousClock()
    let start = clock.now
    var shot = watch.snapshot()
    while !ready(shot) && start.duration(to: clock.now) < timeout {
        try? await Task.sleep(for: .milliseconds(20))
        shot = watch.snapshot()
    }
    return shot
}

private struct TemporaryRecords {
    let root: URL
    let file: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-focus-watch-\(UUID().uuidString)", isDirectory: true)
        file = root.appendingPathComponent("record.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func write(_ text: String) throws {
        let bytes = Data(text.utf8)
        if FileManager.default.fileExists(atPath: file.path) {
            let handle = try FileHandle(forWritingTo: file)
            do {
                try handle.seek(toOffset: 0)
                try handle.write(contentsOf: bytes)
                try handle.truncate(atOffset: UInt64(bytes.count))
                try handle.synchronize()
            } catch {
                try? handle.close()
                throw error
            }
            try handle.close()
        } else {
            try bytes.write(to: file)
        }
    }

    func replace(with text: String) throws {
        let next = root.appendingPathComponent("record.next")
        try Data(text.utf8).write(to: next)
        guard rename(next.path, file.path) == 0 else {
            throw WatchIOError()
        }
    }

    func destroy() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct WatchIOError: Error {}
