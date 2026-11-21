import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// One transcript: a session's, or a Zeus conversation's. A caller that has both uses two stores.
/// The machine is pure. The store writes only into the directory it was given.
public struct HubTranscript: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var status: HubTranscriptStatus
    public var lines: [HubTranscriptLine]

    public init(id: UUID = UUID(), status: HubTranscriptStatus = .idle, lines: [HubTranscriptLine] = []) {
        self.id = id
        self.status = status
        self.lines = lines
    }

    public var isEmpty: Bool {
        !lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// A stored line. `failed` is set for a turn that did not produce an answer. That line is plain text.
public struct HubTranscriptLine: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var role: HubLineRole
    public var text: String
    public var failed: Bool

    public init(id: UUID = UUID(), role: HubLineRole, text: String, failed: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.failed = failed
    }
}

/// What one event did. `writes` is false for a delta and for any pair the target table does not save.
public struct HubTranscriptEffect: Equatable, Sendable {
    public var transcript: HubTranscript
    public var writes: Bool

    public init(transcript: HubTranscript, writes: Bool) {
        self.transcript = transcript
        self.writes = writes
    }
}

/// How a line is drawn. A failed line is the plain string. An agent line is the existing markdown blocks.
public enum HubTranscriptPresentation: Equatable, Sendable {
    case plain(String)
    case markdown([MarkdownBlock])
}

public enum HubTranscriptRendering {
    public static func render(_ line: HubTranscriptLine) -> HubTranscriptPresentation {
        if line.failed || line.role != .agent {
            return .plain(line.text)
        }
        return .markdown(MarkdownBlock.parse(line.text))
    }
}

/// The transcript table in the target. A pair that is not in the table leaves the transcript as it was.
public enum HubTranscriptMachine {
    public static func reduce(
        _ transcript: HubTranscript,
        _ event: HubTranscriptEvent,
        text: String = "",
        lineID: UUID = UUID()
    ) -> HubTranscriptEffect {
        switch (transcript.status, event) {
        case (.idle, .send), (.settled, .send), (.failed, .send):
            return send(transcript, text: text, lineID: lineID)
        case (.streaming, .delta):
            return delta(transcript, text: text, lineID: lineID)
        case (.streaming, .finish):
            return finish(transcript, text: text, lineID: lineID)
        case (.streaming, .finishEmpty):
            return fail(transcript, text: HubTranscriptNotice.noAnswer.storedLabel, lineID: lineID)
        case (.streaming, .stop):
            return stop(transcript, lineID: lineID)
        case (.streaming, .failure):
            return fail(transcript, text: text, lineID: lineID)
        default:
            return HubTranscriptEffect(transcript: transcript, writes: false)
        }
    }

    private static func send(_ transcript: HubTranscript, text: String, lineID: UUID) -> HubTranscriptEffect {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return HubTranscriptEffect(transcript: transcript, writes: false) }
        var next = transcript
        next.status = .streaming
        next.lines.append(HubTranscriptLine(id: lineID, role: .person, text: spoken))
        return HubTranscriptEffect(transcript: next, writes: true)
    }

    /// The text replaces the open agent line. It is not appended, and it is not written.
    private static func delta(_ transcript: HubTranscript, text: String, lineID: UUID) -> HubTranscriptEffect {
        var next = transcript
        next.lines = replaceOpenLine(in: next.lines, id: lineID, role: .agent, text: text, failed: false)
        return HubTranscriptEffect(transcript: next, writes: false)
    }

    private static func finish(_ transcript: HubTranscript, text: String, lineID: UUID) -> HubTranscriptEffect {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = transcript
        if !spoken.isEmpty {
            next.status = .settled
            next.lines = replaceOpenLine(in: next.lines, id: lineID, role: .agent, text: spoken, failed: false)
            return HubTranscriptEffect(transcript: next, writes: true)
        }
        guard let open = openAgentLine(in: transcript.lines),
              !open.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return HubTranscriptEffect(transcript: transcript, writes: false)
        }
        next.status = .settled
        return HubTranscriptEffect(transcript: next, writes: true)
    }

    private static func stop(_ transcript: HubTranscript, lineID: UUID) -> HubTranscriptEffect {
        var next = transcript
        next.status = .settled
        if let open = openAgentLine(in: transcript.lines),
           !open.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return HubTranscriptEffect(transcript: next, writes: true)
        }
        next.lines = replaceOpenLine(
            in: next.lines,
            id: lineID,
            role: .stopped,
            text: HubTranscriptNotice.stopped.storedLabel,
            failed: false
        )
        return HubTranscriptEffect(transcript: next, writes: true)
    }

    private static func fail(_ transcript: HubTranscript, text: String, lineID: UUID) -> HubTranscriptEffect {
        var next = transcript
        next.status = .failed
        next.lines = replaceOpenLine(in: next.lines, id: lineID, role: .failed, text: text, failed: true)
        return HubTranscriptEffect(transcript: next, writes: true)
    }

    /// The open line is the last line, and only while it is still an agent line.
    private static func openAgentLine(in lines: [HubTranscriptLine]) -> HubTranscriptLine? {
        guard let last = lines.last, last.role == .agent, !last.failed else { return nil }
        return last
    }

    private static func replaceOpenLine(
        in lines: [HubTranscriptLine],
        id: UUID,
        role: HubLineRole,
        text: String,
        failed: Bool
    ) -> [HubTranscriptLine] {
        var lines = lines
        if let index = lines.indices.last, lines[index].role == .agent, !lines[index].failed {
            lines[index].role = role
            lines[index].text = text
            lines[index].failed = failed
            return lines
        }
        lines.append(HubTranscriptLine(id: id, role: role, text: text, failed: failed))
        return lines
    }
}

/// Applies the machine and writes only when the effect says to. A delta leaves the directory untouched.
public enum HubTranscriptDriver {
    public static func apply(
        _ transcript: inout HubTranscript,
        _ event: HubTranscriptEvent,
        text: String = "",
        store: HubTranscriptStore,
        lineID: UUID = UUID()
    ) throws {
        let effect = HubTranscriptMachine.reduce(transcript, event, text: text, lineID: lineID)
        transcript = effect.transcript
        if effect.writes {
            try store.write(transcript)
        }
    }
}

/// Thrown when a transcript file or its directory cannot be kept owner-only.
public enum HubTranscriptStoreError: Error, Equatable, Sendable, LocalizedError {
    case cannotSecure(String, Int32)
    case unsafe(String)

    public var errorDescription: String? {
        switch self {
        case .cannotSecure(let action, let code):
            "Could not \(action) (errno \(code))."
        case .unsafe(let kind):
            "Refused an unsafe transcript \(kind)."
        }
    }
}

/// A test seam. The temporary file is synced, then removed, and the previous file stays.
enum HubTranscriptWriteFault: Error, Equatable, Sendable {
    case beforeRename
}

/// One JSON file per transcript, under a directory the caller supplies.
/// The directory is 0700 and each file is 0600, whatever the process umask is.
/// An empty transcript is not written. A replacement is synced, then renamed over the previous file.
public struct HubTranscriptStore: Sendable {
    public let directory: URL
    /// When set, the next replacement stops after the temporary file is synced and before rename.
    var writeFault: HubTranscriptWriteFault?

    public init(directory: URL) {
        self.directory = directory
        self.writeFault = nil
    }

    public func write(_ transcript: HubTranscript) throws {
        guard !transcript.isEmpty else { return }
        try locked(transcript.id) { folder in
            try commit(transcript, folder: folder)
        }
    }

    /// Adds one line under the same lock as `write`, then replaces the file.
    /// A blank line that would leave the transcript empty is not written.
    public func append(_ line: HubTranscriptLine, to id: UUID) throws {
        if !HubTranscriptFiles.exists(directory) {
            let spoken = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spoken.isEmpty else { return }
        }
        try locked(id) { folder in
            var transcript = try read(id, folder: folder) ?? HubTranscript(id: id)
            transcript.lines.append(line)
            guard !transcript.isEmpty else { return }
            try commit(transcript, folder: folder)
        }
    }

    /// A missing file is nil. A second store on the same directory reads what an earlier one wrote.
    public func load(_ id: UUID) -> HubTranscript? {
        guard HubTranscriptFiles.exists(directory) else { return nil }
        return try? locked(id) { folder in
            try read(id, folder: folder)
        }
    }

    private func commit(_ transcript: HubTranscript, folder: Int32) throws {
        try HubTranscriptFiles.replace(
            Self.encoder().encode(transcript),
            folder: folder,
            name: Self.fileName(transcript.id),
            fault: writeFault
        )
    }

    private func read(_ id: UUID, folder: Int32) throws -> HubTranscript? {
        guard let data = try HubTranscriptFiles.read(folder: folder, name: Self.fileName(id)),
              let transcript = try? Self.decoder().decode(HubTranscript.self, from: data),
              transcript.id == id else { return nil }
        return transcript
    }

    private func locked<T>(_ id: UUID, _ body: (Int32) throws -> T) throws -> T {
        let processLock = HubTranscriptProcessLocks.shared.lock(for: Self.lockKey(directory, id))
        processLock.lock()
        defer { processLock.unlock() }
        let folder = try HubTranscriptFiles.openFolder(directory)
        defer { _ = HubPOSIX.close(folder) }
        return try HubTranscriptFiles.withFileLock(folder: folder, name: ".\(id.uuidString).lock") {
            try body(folder)
        }
    }

    private static func fileName(_ id: UUID) -> String { "\(id.uuidString).json" }

    private static func lockKey(_ directory: URL, _ id: UUID) -> String {
        directory.path + "\n" + id.uuidString
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder { JSONDecoder() }
}

/// In-process serialization. `flock` covers a second process; this covers threads in this one.
private final class HubTranscriptProcessLock: @unchecked Sendable {
    private let mutex = NSLock()
    func lock() { mutex.lock() }
    func unlock() { mutex.unlock() }
}

private final class HubTranscriptProcessLocks: @unchecked Sendable {
    static let shared = HubTranscriptProcessLocks()
    private let gate = NSLock()
    private var locks: [String: HubTranscriptProcessLock] = [:]

    func lock(for key: String) -> HubTranscriptProcessLock {
        gate.lock()
        defer { gate.unlock() }
        if let existing = locks[key] { return existing }
        let created = HubTranscriptProcessLock()
        locks[key] = created
        return created
    }
}

private enum HubPOSIX {
    static func close(_ fd: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.close(fd)
        #else
        Glibc.close(fd)
        #endif
    }

    static func write(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.write(fd, buffer, count)
        #else
        Glibc.write(fd, buffer, count)
        #endif
    }

    static func read(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.read(fd, buffer, count)
        #else
        Glibc.read(fd, buffer, count)
        #endif
    }
}

private enum HubTranscriptFiles {
    static func exists(_ directory: URL) -> Bool {
        guard let path = try? absolute(directory) else { return false }
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    static func openFolder(_ directory: URL) throws -> Int32 {
        let path = try absolute(directory)
        try ensure(path)
        let folder = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard folder >= 0 else { throw io("open the transcript directory", errno) }
        do {
            if fchmod(folder, mode_t(0o700)) != 0 { throw io("restrict the transcript directory", errno) }
            var info = stat()
            guard fstat(folder, &info) == 0 else { throw io("inspect the transcript directory", errno) }
            try requireDirectory(info)
            return folder
        } catch {
            _ = HubPOSIX.close(folder)
            throw error
        }
    }

    static func withFileLock<T>(folder: Int32, name: String, _ body: () throws -> T) throws -> T {
        let lock = try openLock(folder: folder, name: name)
        defer { _ = HubPOSIX.close(lock) }
        while flock(lock, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw io("lock the transcript", errno)
        }
        defer { _ = flock(lock, LOCK_UN) }
        return try body()
    }

    static func replace(_ data: Data, folder: Int32, name: String, fault: HubTranscriptWriteFault?) throws {
        let temporary = ".\(name).\(UUID().uuidString).tmp"
        let file = temporary.withCString {
            openat(folder, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        }
        guard file >= 0 else { throw io("create the temporary transcript", errno) }
        var open = true
        do {
            if fchmod(file, mode_t(0o600)) != 0 { throw io("restrict the temporary transcript", errno) }
            var info = stat()
            guard fstat(file, &info) == 0 else { throw io("inspect the temporary transcript", errno) }
            try requireFile(info)
            try writeAll(file, data)
            if fsync(file) != 0 { throw io("sync the temporary transcript", errno) }
            if HubPOSIX.close(file) != 0 {
                open = false
                throw io("close the temporary transcript", errno)
            }
            open = false
            if fault == .beforeRename {
                unlink(folder, temporary)
                throw HubTranscriptWriteFault.beforeRename
            }
            let renamed = temporary.withCString { source in
                name.withCString { destination in
                    renameat(folder, source, folder, destination)
                }
            }
            if renamed != 0 { throw io("replace the transcript", errno) }
            if fsync(folder) != 0 { throw io("sync the transcript directory", errno) }
        } catch {
            if open { _ = HubPOSIX.close(file) }
            unlink(folder, temporary)
            throw error
        }
    }

    static func read(folder: Int32, name: String) throws -> Data? {
        let file = name.withCString { openat(folder, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard file >= 0 else {
            if errno == ENOENT { return nil }
            throw io("open the transcript", errno)
        }
        defer { _ = HubPOSIX.close(file) }
        var info = stat()
        guard fstat(file, &info) == 0 else { throw io("inspect the transcript", errno) }
        try requireFile(info)
        return try readAll(file)
    }

    private static func absolute(_ directory: URL) throws -> String {
        let path = directory.path
        guard !path.isEmpty, !path.utf8.contains(0) else { throw HubTranscriptStoreError.unsafe("directory") }
        if path.hasPrefix("/") { return path }
        let current = FileManager.default.currentDirectoryPath
        return current.hasSuffix("/") ? current + path : current + "/" + path
    }

    private static func ensure(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard path.hasPrefix("/"), !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw HubTranscriptStoreError.unsafe("directory")
        }
        var built = ""
        for (index, part) in parts.enumerated() {
            built += "/" + part
            let leaf = index == parts.count - 1
            var info = stat()
            if lstat(built, &info) == 0 {
                if (info.st_mode & S_IFMT) != S_IFDIR { throw HubTranscriptStoreError.unsafe("directory") }
                if leaf, chmod(built, mode_t(0o700)) != 0 { throw io("restrict the transcript directory", errno) }
                continue
            }
            if errno != ENOENT { throw io("inspect the transcript directory", errno) }
            if mkdir(built, mode_t(0o700)) != 0, errno != EEXIST { throw io("create the transcript directory", errno) }
            if chmod(built, mode_t(0o700)) != 0 { throw io("restrict the transcript directory", errno) }
        }
    }

    private static func openLock(folder: Int32, name: String) throws -> Int32 {
        func openIt() -> Int32 {
            name.withCString { openat(folder, $0, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600)) }
        }
        var lock = openIt()
        if lock < 0, errno == EACCES,
           name.withCString({ fchmodat(folder, $0, mode_t(0o600), AT_SYMLINK_NOFOLLOW) }) == 0 {
            lock = openIt()
        }
        guard lock >= 0 else { throw io("open the transcript lock", errno) }
        if fchmod(lock, mode_t(0o600)) != 0 {
            _ = HubPOSIX.close(lock)
            throw io("restrict the transcript lock", errno)
        }
        var info = stat()
        guard fstat(lock, &info) == 0 else {
            _ = HubPOSIX.close(lock)
            throw io("inspect the transcript lock", errno)
        }
        do { try requireFile(info) } catch {
            _ = HubPOSIX.close(lock)
            throw error
        }
        return lock
    }

    private static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let wrote = HubPOSIX.write(fd, base.advanced(by: offset), buffer.count - offset)
                if wrote < 0 {
                    if errno == EINTR { continue }
                    throw io("write the temporary transcript", errno)
                }
                if wrote == 0 { throw io("write the temporary transcript", errno) }
                offset += wrote
            }
        }
    }

    private static func readAll(_ fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let amount = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return HubPOSIX.read(fd, base, raw.count)
            }
            if amount < 0 {
                if errno == EINTR { continue }
                throw io("read the transcript", errno)
            }
            if amount == 0 { return data }
            data.append(contentsOf: buffer.prefix(amount))
        }
    }

    private static func requireDirectory(_ info: stat) throws {
        guard (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == getuid(),
              (info.st_mode & mode_t(0o777)) == mode_t(0o700) else {
            throw HubTranscriptStoreError.unsafe("directory")
        }
    }

    private static func requireFile(_ info: stat) throws {
        guard (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              info.st_nlink == 1,
              (info.st_mode & mode_t(0o777)) == mode_t(0o600) else {
            throw HubTranscriptStoreError.unsafe("file")
        }
    }

    private static func unlink(_ folder: Int32, _ name: String) {
        _ = name.withCString { unlinkat(folder, $0, 0) }
    }

    private static func io(_ action: String, _ code: Int32) -> HubTranscriptStoreError {
        .cannotSecure(action, code)
    }
}
