import Foundation
import ZeusCore

public enum FlingSinkError: Error { case unsafePath, io(Int32), notOpen }

/// Where one arriving stack is written. Bytes go to a hidden partial folder (mode 0600, created exclusively) while
/// the SHA-256 is computed on the way in. A file becomes visible only when `commit` moves it into the stack folder.
public final class FlingFileSink {
    public static let partialPrefix = ".fling-partial-"

    private let partial: URL
    private let destination: URL
    private var handle: FileHandle?
    private var handleIndex: Int?
    private var hasher = FlingHasher()
    private var wrote: Int64 = 0
    private var folder: URL?

    /// `partialParent` is where the hidden folder goes; `destination` is the stack folder the files end up in.
    public init(stackID: UUID, partialParent: URL, destination: URL) {
        self.partial = partialParent.appendingPathComponent(Self.partialPrefix + stackID.uuidString, isDirectory: true)
        self.destination = destination
    }

    public var partialFolder: URL { partial }

    public func makeTemp() throws {
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    public func write(index: Int, data: Data) throws {
        if handleIndex != index {
            try closeHandle()
            let path = partial.appendingPathComponent(String(index)).path
            let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard fd >= 0 else { throw FlingSinkError.io(errno) }
            handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            handleIndex = index
            hasher = FlingHasher()
            wrote = 0
        }
        guard let handle else { throw FlingSinkError.notOpen }
        do { try handle.write(contentsOf: data) } catch { throw FlingSinkError.io(errno) }
        hasher.update(data)
        wrote += Int64(data.count)
    }

    private func closeHandle() throws {
        try handle?.close()
        handle = nil
        handleIndex = nil
    }

    /// Closes the file and returns its SHA-256. A zero-byte file that never received a chunk is created empty.
    public func verify(index: Int) throws -> String {
        if handleIndex != index {
            try closeHandle()
            let path = partial.appendingPathComponent(String(index)).path
            let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard fd >= 0 else { throw FlingSinkError.io(errno) }
            close(fd)
            return FlingHasher().finalHex()
        }
        try closeHandle()
        return hasher.finalHex()
    }

    private func stackFolder() throws -> URL {
        if let folder { return folder }
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        var name = destination.lastPathComponent
        let existing = Set((try? fm.contentsOfDirectory(atPath: parent.path)) ?? [])
        name = FlingNames.freeName(name, taken: existing)
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        folder = url
        return url
    }

    private func target(for name: String) throws -> URL {
        guard case .success(let safe) = FlingNames.validate(name) else { throw FlingSinkError.unsafePath }
        let dir = try stackFolder()
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        let url = dir.appendingPathComponent(FlingNames.freeName(safe, taken: taken))
        guard FlingNames.isContained(url, in: dir) else { throw FlingSinkError.unsafePath }
        return url
    }

    @discardableResult
    public func commit(index: Int, name: String) throws -> URL {
        let url = try target(for: name)
        try FileManager.default.moveItem(at: partial.appendingPathComponent(String(index)), to: url)
        return url
    }

    @discardableResult
    public func commitLink(name: String, link: String) throws -> URL {
        let url = try target(for: FlingSaveRules.linkFileName(name))
        try FlingSaveRules.weblocData(for: link).write(to: url, options: .atomic)
        return url
    }

    /// Removes the partial folder and anything in it. Safe to call more than once.
    public func deleteTemp() {
        try? closeHandle()
        try? FileManager.default.removeItem(at: partial)
    }

    /// After a finished stack: removes the hidden folder, which is empty by now.
    public func finish() { deleteTemp() }

    /// Launch sweep: deletes hidden partial folders older than `olderThan` seconds directly inside each directory.
    public static func sweep(directories: [URL], olderThan: TimeInterval = 3600, now: Date = Date()) {
        let fm = FileManager.default
        for dir in directories {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasPrefix(partialPrefix) {
                let url = dir.appendingPathComponent(name)
                let modified = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date ?? .distantPast
                if now.timeIntervalSince(modified) > olderThan { try? fm.removeItem(at: url) }
            }
        }
    }
}
