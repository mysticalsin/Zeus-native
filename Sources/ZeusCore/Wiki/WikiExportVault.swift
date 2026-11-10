import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A deliberately small filesystem capability: create/read only UUID-named export notes in
/// one selected inbox. Directory descriptors and O_NOFOLLOW prevent symlink redirection.
/// The selected root's device/inode must still match the reviewed destination.
public final class WikiExportVault: @unchecked Sendable {
    private let rootFD: Int32
    private let inboxComponents: [String]
    public let inbox: String

    public static func identity(of root: URL) throws -> String {
        guard root.isFileURL, !root.path.contains("\0") else { throw WikiExportError.destination("Choose a local vault folder.") }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw filesystemError("The selected vault could not be opened") }
        defer { close(fd) }
        return try identity(fd)
    }

    private static func identity(_ fd: Int32) throws -> String {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw filesystemError("The selected vault could not be checked") }
        return "\(info.st_dev):\(info.st_ino)"
    }

    public static func validateInbox(_ inbox: String) throws {
        let components = inbox.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= 8,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".")
                  && $0.utf8.count <= 200 && !$0.contains("\\") && !$0.contains(where: \.isNewline)
                  && !$0.contains("\0") }) else {
            throw WikiExportError.destination("Choose a normal, non-hidden inbox folder inside the selected vault.")
        }
    }

    public init(root: URL, inbox: String, expectedIdentity: String) throws {
        try Self.validateInbox(inbox)
        guard root.isFileURL, !root.path.contains("\0") else { throw WikiExportError.destination("Choose a local vault folder.") }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Self.filesystemError("The selected vault could not be opened") }
        do {
            guard try Self.identity(fd) == expectedIdentity else { throw WikiExportError.staleDraft }
        } catch {
            close(fd)
            throw error
        }
        rootFD = fd
        self.inbox = inbox
        inboxComponents = inbox.split(separator: "/").map(String.init)
    }

    deinit { close(rootFD) }

    public static func fileName(_ id: UUID) -> String { "zeus-memory-\(id.uuidString.lowercased()).md" }

    /// nil means absent. It never follows a link, reads arbitrary paths, or creates directories.
    public func inspect(exportID: UUID) throws -> String? {
        guard let folder = try openInbox(create: false) else { return nil }
        defer { close(folder) }
        return try readNote(exportID: exportID, folder: folder)
    }

    /// Publishes a complete file with linkat's exclusive destination semantics. A crash cannot
    /// expose a partial Markdown note. An identical retry returns the existing note unchanged.
    public func create(exportID: UUID, markdown: String) throws {
        let bytes = Data(markdown.utf8)
        guard !bytes.isEmpty, bytes.count <= WikiExportDraft.maxBytes else { throw WikiExportError.tooLarge }
        guard let folder = try openInbox(create: true) else { throw Self.filesystemError("The inbox could not be opened") }
        defer { close(folder) }
        if let existing = try readNote(exportID: exportID, folder: folder) {
            guard Data(existing.utf8) == bytes else { throw WikiExportError.conflict }
            return
        }
        let temporary = ".zeus-export-\(UUID().uuidString.lowercased()).tmp"
        let file = openat(folder, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard file >= 0 else { throw Self.filesystemError("The new export could not be created") }
        defer { close(file); _ = unlinkat(folder, temporary, 0) }
        try bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(file, base.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw Self.filesystemError("The new export could not be written") }
                offset += written
            }
        }
        guard fsync(file) == 0 else { throw Self.filesystemError("The new export could not be saved") }
        if linkat(folder, temporary, folder, Self.fileName(exportID), 0) != 0 {
            guard errno == EEXIST else { throw Self.filesystemError("The new export could not be published") }
            guard let existing = try readNote(exportID: exportID, folder: folder), Data(existing.utf8) == bytes else {
                throw WikiExportError.conflict
            }
        }
        // Some filesystems do not support syncing directories. The note itself was fsynced.
        _ = fsync(folder)
    }

    private func openInbox(create: Bool) throws -> Int32? {
        var current = dup(rootFD)
        guard current >= 0 else { throw Self.filesystemError("The selected vault could not be opened") }
        do {
            for component in inboxComponents {
                if create, mkdirat(current, component, mode_t(0o700)) != 0 && errno != EEXIST {
                    throw Self.filesystemError("The selected inbox could not be created")
                }
                let next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0 {
                    if !create && errno == ENOENT { close(current); return nil }
                    throw Self.filesystemError("The selected inbox is unavailable or contains a symbolic link")
                }
                close(current)
                current = next
            }
            return current
        } catch { close(current); throw error }
    }

    private func readNote(exportID: UUID, folder: Int32) throws -> String? {
        let fd = openat(folder, Self.fileName(exportID), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw Self.filesystemError("The export note could not be checked")
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_nlink == 1, info.st_size >= 0, info.st_size <= WikiExportDraft.maxBytes else { throw WikiExportError.conflict }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw Self.filesystemError("The export note could not be read back") }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= WikiExportDraft.maxBytes else { throw WikiExportError.conflict }
        }
        guard let text = String(data: data, encoding: .utf8) else { throw WikiExportError.conflict }
        return text
    }

    private static func filesystemError(_ message: String) -> WikiExportError {
        .destination("\(message). \(String(cString: strerror(errno)))")
    }
}
