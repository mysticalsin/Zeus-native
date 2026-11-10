import Darwin
import Foundation

/// Narrow checkpoint of a *finalized* Recordly project plus lazy restore.
///
/// Scope: one "latest" record, written after capture has finished and restored only on a user action.
/// It does not cover interrupted capture, export, automatic startup restore, or power-loss durability:
/// the commit is a rename of a fully written temp file and never calls fsync.
///
/// Every filesystem step walks from "/" with descriptor-relative `openat` and `O_NOFOLLOW`, so a symlink in
/// any ancestor or leaf of a trusted root, the media path, or the record is refused. The media path is checked
/// lexically against the injected trusted media root before any filesystem call. Roots are always injected
/// and never read from the checkpoint JSON.
public struct RecordlyCheckpointStore: Sendable {
    public static let recordName = "latest.zeuscast.json"
    public static let checkpointDirectoryName = "Checkpoints"
    public static let defaultMaxRecordBytes = 16 * 1024 * 1024

    public enum StoreError: Error, Equatable, LocalizedError, Sendable {
        case invalidRoot(String)
        case mediaOutsideTrustedRoot
        case pathEscape
        case notFound
        case mediaMissing
        case mediaEmpty
        case mediaNotRegularFile
        case mediaHardLinked
        case mediaReleased
        case mediaChanged
        case mediaTooLargeForPreview
        case readOutOfRange
        case checkpointNotRegularFile
        case checkpointHardLinked
        case unsupportedVersion(Int)
        case corrupt
        case tooLarge
        case encodingFailed
        case system(operation: String, code: Int32)

        public var errorDescription: String? {
            switch self {
            case .invalidRoot(let which): "The \(which) folder path is not a clean absolute path."
            case .mediaOutsideTrustedRoot: "The recording is outside Zeus's Recordly folder, so it cannot be checkpointed."
            case .pathEscape: "A symbolic link or non-folder was found in the checkpoint or recording path, so it was refused."
            case .notFound: "The checkpoint folder or file does not exist."
            case .mediaMissing: "The recording file is missing."
            case .mediaEmpty: "The recording file is empty."
            case .mediaNotRegularFile: "The recording path is not a regular file."
            case .mediaHardLinked: "The recording file has more than one hard link, so it was refused."
            case .mediaReleased: "The recording handle was already released."
            case .mediaChanged: "The recording changed while it was being read, so the read was refused."
            case .mediaTooLargeForPreview: "The recording is larger than the 512 MiB preview limit."
            case .readOutOfRange: "The requested recording range is invalid."
            case .checkpointNotRegularFile: "The checkpoint record is not a regular file."
            case .checkpointHardLinked: "The checkpoint record has more than one hard link, so it was refused."
            case .unsupportedVersion(let version): "The checkpoint uses unsupported project version \(version)."
            case .corrupt: "The checkpoint record is unreadable."
            case .tooLarge: "The checkpoint record is larger than the allowed size."
            case .encodingFailed: "The project could not be encoded for the checkpoint."
            case .system(let operation, let code): "Checkpoint \(operation) failed (errno \(code))."
            }
        }
    }

    /// Points inside a save where tests can inject a failure.
    public enum FaultStage: Sendable, CaseIterable {
        case afterTempCreate
        case afterTempWrite
        case beforeRename
    }

    public enum LoadResult: Equatable, Sendable {
        case absent
        case found(RecordlyProject, media: RecordlyValidatedMedia)
    }

    public let mediaRoot: String
    public let checkpointRoot: String
    public let maxRecordBytes: Int
    public var faultHook: (@Sendable (FaultStage) throws -> Void)?

    public init(
        mediaRoot: String,
        checkpointRoot: String,
        maxRecordBytes: Int = RecordlyCheckpointStore.defaultMaxRecordBytes,
        faultHook: (@Sendable (FaultStage) throws -> Void)? = nil
    ) {
        self.mediaRoot = mediaRoot
        self.checkpointRoot = checkpointRoot
        self.maxRecordBytes = maxRecordBytes
        self.faultHook = faultHook
    }

    /// App-owned roots under Application Support/Zeus/Recordly. Call only from a finalize or user-source-load
    /// action; nothing here touches the filesystem beyond asking Foundation for the Application Support URL.
    public static func makeProduction() -> RecordlyCheckpointStore? {
        guard let base = productionMediaRootURL()?.path else { return nil }
        return RecordlyCheckpointStore(mediaRoot: base, checkpointRoot: base + "/" + checkpointDirectoryName)
    }

    /// The single trusted, app-owned media root. Capture output and the store's media root both come from here.
    /// No filesystem access beyond asking Foundation for the Application Support URL.
    public static func productionMediaRootURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support.appendingPathComponent("Zeus/Recordly", isDirectory: true)
    }

    // MARK: Save

    /// Validates the media, then commits the record by writing a temp file and renaming it over the record.
    /// On any failure the previously committed record is left in place and the temp file is removed.
    public func save(_ project: RecordlyProject) throws {
        guard project.version == RecordlyProject.formatVersion else {
            throw StoreError.unsupportedVersion(project.version)
        }
        let relativeMedia = try trustedRelativeMediaComponents(project.rawMediaPath)
        let checkpointParts = try Self.rootComponents(checkpointRoot, label: "checkpoint")
        let data: Data
        do { data = try project.encoded() } catch { throw StoreError.encodingFailed }
        guard data.count <= maxRecordBytes else { throw StoreError.tooLarge }
        _ = try verifyMedia(relativeMedia)

        let parentFD = try Self.openDirectory(Array(checkpointParts.dropLast()))
        defer { Darwin.close(parentFD) }
        let leaf = checkpointParts[checkpointParts.count - 1]
        if mkdirat(parentFD, leaf, 0o700) != 0 {
            let code = errno
            if code != EEXIST { throw Self.mapped(code, "create checkpoint folder") }
        }
        let dirFD = openat(parentFD, leaf, Self.directoryFlags)
        guard dirFD >= 0 else { throw Self.mapped(errno, "open checkpoint folder") }
        defer { Darwin.close(dirFD) }

        let tempName = ".latest-\(UUID().uuidString).tmp"
        let tempFD = openat(dirFD, tempName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard tempFD >= 0 else { throw Self.mapped(errno, "create temp record") }
        var tempOpen = true
        do {
            try faultHook?(.afterTempCreate)
            try Self.writeAll(tempFD, data)
            try faultHook?(.afterTempWrite)
            Darwin.close(tempFD)
            tempOpen = false
            try faultHook?(.beforeRename)
            guard renameat(dirFD, tempName, dirFD, Self.recordName) == 0 else {
                throw Self.mapped(errno, "commit record")
            }
        } catch {
            if tempOpen { Darwin.close(tempFD) }
            unlinkat(dirFD, tempName, 0)
            throw error
        }
    }

    // MARK: Load

    /// Reads the record without modifying anything. Missing checkpoint folder or record is `.absent`.
    /// Version and size are checked before the project is decoded, and the media is re-verified under the trusted root.
    public func load() throws -> LoadResult {
        let checkpointParts = try Self.rootComponents(checkpointRoot, label: "checkpoint")
        let dirFD: Int32
        do {
            dirFD = try Self.openDirectory(checkpointParts)
        } catch StoreError.notFound {
            return .absent
        }
        defer { Darwin.close(dirFD) }

        let fileFD = openat(dirFD, Self.recordName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fileFD >= 0 else {
            let code = errno
            if code == ENOENT { return .absent }
            throw Self.mapped(code, "open record")
        }
        defer { Darwin.close(fileFD) }

        var info = stat()
        guard fstat(fileFD, &info) == 0 else { throw Self.mapped(errno, "inspect record") }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw StoreError.checkpointNotRegularFile }
        guard info.st_nlink == 1 else { throw StoreError.checkpointHardLinked }
        guard info.st_size <= Int64(maxRecordBytes) else { throw StoreError.tooLarge }

        let data = try Self.readAll(fileFD, limit: maxRecordBytes)

        struct VersionProbe: Decodable { let version: Int }
        let probe: VersionProbe
        do { probe = try JSONDecoder().decode(VersionProbe.self, from: data) } catch { throw StoreError.corrupt }
        guard probe.version == RecordlyProject.formatVersion else {
            throw StoreError.unsupportedVersion(probe.version)
        }
        let project: RecordlyProject
        do { project = try RecordlyProject.decode(data) } catch { throw StoreError.corrupt }

        let relativeMedia = try trustedRelativeMediaComponents(project.rawMediaPath)
        let media = try verifyMedia(relativeMedia, path: project.rawMediaPath)
        return .found(project, media: media)
    }

    /// Pins the media for a project that was just finalized or restored, without writing a record. The same lexical
    /// trusted-root check and descriptor walk as `save` and `load` apply; nothing here reopens the path later.
    public func openValidatedMedia(rawPath: String) throws -> RecordlyValidatedMedia {
        let relativeMedia = try trustedRelativeMediaComponents(rawPath)
        return try verifyMedia(relativeMedia, path: rawPath)
    }

    // MARK: Path and media checks

    private static let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC

    /// Components of a clean absolute path; nil for relative paths, "/" itself, empty, "." or ".." components, or NUL.
    static func components(ofAbsolute path: String) -> [String]? {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
        var parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        parts.removeFirst()
        if parts.last == "" { parts.removeLast() }
        guard !parts.isEmpty else { return nil }
        for part in parts where part.isEmpty || part == "." || part == ".." { return nil }
        return parts
    }

    private static func rootComponents(_ path: String, label: String) throws -> [String] {
        guard let parts = components(ofAbsolute: path) else { throw StoreError.invalidRoot(label) }
        return parts
    }

    /// Lexical only, no filesystem access: the media must sit strictly under the trusted media root and never
    /// inside the checkpoint folder.
    private func trustedRelativeMediaComponents(_ rawPath: String) throws -> [String] {
        let root = try Self.rootComponents(mediaRoot, label: "recording")
        let checkpoint = try Self.rootComponents(checkpointRoot, label: "checkpoint")
        guard let media = Self.components(ofAbsolute: rawPath),
              media.count > root.count,
              Array(media.prefix(root.count)) == root
        else { throw StoreError.mediaOutsideTrustedRoot }
        if media.count >= checkpoint.count, Array(media.prefix(checkpoint.count)) == checkpoint {
            throw StoreError.mediaOutsideTrustedRoot
        }
        return Array(media.dropFirst(root.count))
    }

    /// Opens the media through descriptors from the trusted root and requires a non-empty, singly linked regular
    /// file. The validated descriptor is kept open inside the returned handle, so callers hold the validated
    /// inode rather than a pathname that could be swapped afterwards.
    private func verifyMedia(_ relative: [String], path: String = "") throws -> RecordlyValidatedMedia {
        let rootParts = try Self.rootComponents(mediaRoot, label: "recording")
        do {
            var current = try Self.openDirectory(rootParts)
            defer { Darwin.close(current) }
            for name in relative.dropLast() {
                let next = openat(current, name, Self.directoryFlags)
                let code = errno
                guard next >= 0 else { throw Self.mapped(code, "open recording folder") }
                Darwin.close(current)
                current = next
            }
            let fileFD = openat(current, relative[relative.count - 1], O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fileFD >= 0 else { throw Self.mapped(errno, "open recording") }
            var handedOff = false
            defer { if !handedOff { Darwin.close(fileFD) } }
            var info = stat()
            guard fstat(fileFD, &info) == 0 else { throw Self.mapped(errno, "inspect recording") }
            guard (info.st_mode & S_IFMT) == S_IFREG else { throw StoreError.mediaNotRegularFile }
            guard info.st_nlink == 1 else { throw StoreError.mediaHardLinked }
            guard info.st_size > 0 else { throw StoreError.mediaEmpty }
            handedOff = true
            return RecordlyValidatedMedia(
                path: path,
                descriptor: fileFD,
                device: UInt64(info.st_dev),
                inode: UInt64(info.st_ino),
                byteCount: Int64(info.st_size)
            )
        } catch StoreError.notFound {
            throw StoreError.mediaMissing
        }
    }

    /// Walks from "/" one component at a time, refusing symlinks at every step. The caller closes the result.
    private static func openDirectory(_ parts: [String]) throws -> Int32 {
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else { throw mapped(errno, "open filesystem root") }
        for name in parts {
            let next = openat(current, name, directoryFlags)
            let code = errno
            Darwin.close(current)
            guard next >= 0 else { throw mapped(code, "open folder") }
            current = next
        }
        return current
    }

    private static func mapped(_ code: Int32, _ operation: String) -> StoreError {
        switch code {
        case ENOENT: .notFound
        case ELOOP, ENOTDIR: .pathEscape
        default: .system(operation: operation, code: code)
        }
    }

    private static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard var cursor = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, cursor, remaining)
                if written < 0 {
                    let code = errno
                    if code == EINTR { continue }
                    throw mapped(code, "write temp record")
                }
                cursor = cursor.advanced(by: written)
                remaining -= written
            }
        }
    }

    private static func readAll(_ fd: Int32, limit: Int) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.count
            let got = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, count) }
            if got < 0 {
                let code = errno
                if code == EINTR { continue }
                throw mapped(code, "read record")
            }
            if got == 0 { return data }
            data.append(contentsOf: buffer[0..<got])
            if data.count > limit { throw StoreError.tooLarge }
        }
    }
}

/// Owns the descriptor that validated a recording, so the validated inode stays the authority after the pathname
/// is renamed, replaced or turned into a symlink. `path` is the decoded string for display and diagnostics only
/// and must never be reopened. Consumers go through `withDescriptor` or `readBounded`. Identity, size and link
/// count are observations made before and after each bounded read, and a violation fails closed. They do not make
/// the contents immutable and do not prevent a link or write from happening between observations.
public final class RecordlyValidatedMedia: @unchecked Sendable, Equatable {
    public enum ReadPurpose: Equatable, Sendable {
        case preview
        /// Export streams the pinned file in bounded chunks; its size must stay exactly as pinned.
        case export
    }
    /// Largest file a bounded preview will serve.
    public static let maxPreviewBytes: Int64 = 512 * 1024 * 1024
    /// Largest single allocation and `pread` of `readBounded`.
    public static let maxReadChunk = 64 * 1024

    public let path: String
    public let device: UInt64
    public let inode: UInt64
    public let byteCount: Int64
    private let lock = NSLock()
    private var descriptor: Int32

    init(path: String, descriptor: Int32, device: UInt64, inode: UInt64, byteCount: Int64) {
        self.path = path
        self.descriptor = descriptor
        self.device = device
        self.inode = inode
        self.byteCount = byteCount
    }

    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

    public var isReleased: Bool {
        lock.lock()
        defer { lock.unlock() }
        return descriptor < 0
    }

    /// Runs `body` on the pinned descriptor. The lock is held, so `close()` cannot run concurrently; do not
    /// call back into this handle from `body`.
    public func withDescriptor<T>(_ body: (Int32) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor >= 0 else { throw RecordlyCheckpointStore.StoreError.mediaReleased }
        return try body(descriptor)
    }

    /// Re-inspects the pinned descriptor itself (never the path): same inode, regular, non-empty, singly linked.
    public func revalidate() throws {
        _ = try withDescriptor { fd in try self.inspect(fd) }
    }

    /// Reads at most `min(length, maxReadChunk)` bytes at `offset` from the pinned descriptor, never by path.
    /// Returns empty Data at or past end of file. The descriptor is inspected before and after the read; a changed
    /// identity, link count, or size (or a short file) throws instead of returning bytes. When `expectedSize` is
    /// given, the size observed before the read must equal it.
    public func readBounded(offset: Int64, length: Int, expectedSize: Int64? = nil, purpose: ReadPurpose = .preview) throws -> Data {
        guard offset >= 0, length >= 0 else { throw RecordlyCheckpointStore.StoreError.readOutOfRange }
        return try withDescriptor { (fd: Int32) throws -> Data in
            let before = try self.inspect(fd)
            if purpose == .preview, before > Self.maxPreviewBytes {
                throw RecordlyCheckpointStore.StoreError.mediaTooLargeForPreview
            }
            if purpose == .export, before != self.byteCount { throw RecordlyCheckpointStore.StoreError.mediaChanged }
            if let expectedSize, before != expectedSize { throw RecordlyCheckpointStore.StoreError.mediaChanged }
            guard offset < before, length > 0 else { return Data() }
            let count = Int(min(Int64(min(length, Self.maxReadChunk)), before - offset))
            var buffer = [UInt8](repeating: 0, count: count)
            var filled = 0
            while filled < count {
                let got = buffer.withUnsafeMutableBytes { raw in
                    Darwin.pread(fd, raw.baseAddress!.advanced(by: filled), count - filled, off_t(offset + Int64(filled)))
                }
                if got < 0 {
                    let code = errno
                    if code == EINTR { continue }
                    throw RecordlyCheckpointStore.StoreError.system(operation: "read recording", code: code)
                }
                if got == 0 { throw RecordlyCheckpointStore.StoreError.mediaChanged }
                filled += got
            }
            let after = try self.inspect(fd)
            guard after == before else { throw RecordlyCheckpointStore.StoreError.mediaChanged }
            return Data(buffer)
        }
    }

    /// Lock-free; callers must already hold the lock through `withDescriptor`. Returns the observed size.
    private func inspect(_ fd: Int32) throws -> Int64 {
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            throw RecordlyCheckpointStore.StoreError.system(operation: "inspect recording", code: errno)
        }
        guard UInt64(info.st_dev) == device, UInt64(info.st_ino) == inode,
              (info.st_mode & S_IFMT) == S_IFREG
        else { throw RecordlyCheckpointStore.StoreError.mediaNotRegularFile }
        guard info.st_nlink == 1 else { throw RecordlyCheckpointStore.StoreError.mediaHardLinked }
        guard info.st_size > 0 else { throw RecordlyCheckpointStore.StoreError.mediaEmpty }
        return Int64(info.st_size)
    }

    /// Idempotent.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
    }

    public static func == (lhs: RecordlyValidatedMedia, rhs: RecordlyValidatedMedia) -> Bool {
        lhs.device == rhs.device && lhs.inode == rhs.inode
    }
}

/// Pure decision seam the Controller drives: finalize+commit, retry of the same retained project, and one lazy restore.
/// It holds no filesystem state itself; the store is passed lazily so skipped paths never resolve a root.
public struct RecordlyCheckpointFlow: Sendable {
    public struct Pending: Equatable, Sendable {
        public let project: RecordlyProject
        public let mediaURL: URL
    }

    public enum CommitResult: Equatable, Sendable {
        case committed
        case failed(String)
    }

    public enum RestoreResult: Equatable, Sendable {
        case skipped
        case noCheckpoint
        case restored(RecordlyProject, media: RecordlyValidatedMedia)
        case failed(String)
    }

    public private(set) var pending: Pending?
    public private(set) var restoreAttempted = false

    public var hasPending: Bool { pending != nil }

    public init() {}

    /// Records the completed project as pending and tries to commit it. A recording made this session also
    /// retires the lazy restore, so an older checkpoint never replaces it later.
    public mutating func finalize(
        project: RecordlyProject,
        mediaURL: URL,
        store: @autoclosure () -> RecordlyCheckpointStore?
    ) -> CommitResult {
        restoreAttempted = true
        pending = Pending(project: project, mediaURL: mediaURL)
        return commitPending(store())
    }

    /// Retries the SAME retained project. Nil when nothing is pending, so ordinary retry semantics stay with the caller.
    public mutating func retryPending(store: @autoclosure () -> RecordlyCheckpointStore?) -> CommitResult? {
        guard pending != nil else { return nil }
        return commitPending(store())
    }

    /// Drops an abandoned pending save, for example when the user starts a new recording. Never touches files.
    public mutating func discardPending() {
        pending = nil
    }

    /// Restores at most once. Failures never modify the checkpoint or the media.
    public mutating func restoreIfNeeded(store: @autoclosure () -> RecordlyCheckpointStore?) -> RestoreResult {
        guard !restoreAttempted else { return .skipped }
        restoreAttempted = true
        guard let store = store() else { return .noCheckpoint }
        do {
            switch try store.load() {
            case .absent:
                return .noCheckpoint
            case .found(let project, let media):
                return .restored(project, media: media)
            }
        } catch {
            return .failed(
                "The saved recording checkpoint could not be restored (\(error.localizedDescription)) "
                    + "The checkpoint and the recording file were left untouched."
            )
        }
    }

    private mutating func commitPending(_ store: RecordlyCheckpointStore?) -> CommitResult {
        guard let pending else { return .committed }
        guard let store else {
            return .failed(
                "The recording finished, but Zeus's checkpoint folder is unavailable. "
                    + "The project is kept in memory and the recording file was not deleted. Choose Retry to save it again."
            )
        }
        do {
            try store.save(pending.project)
            self.pending = nil
            return .committed
        } catch {
            return .failed(
                "The recording finished, but its checkpoint could not be saved (\(error.localizedDescription)) "
                    + "The project is kept in memory and the recording file was not deleted. Choose Retry to save it again."
            )
        }
    }
}
