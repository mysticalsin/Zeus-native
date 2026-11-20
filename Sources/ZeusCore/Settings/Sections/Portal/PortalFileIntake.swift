import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct PortalLoadedFile: Equatable, Sendable {
    public var displayName: String
    public var bytes: Data
}

public enum PortalExternalDrop {
    /// Reads a drop the person named. Symlinks are refused at every component. The read stops at the size cap.
    public static func read(path: String, declaredType: PortalFileType) -> Result<PortalLoadedFile, PortalDropFailure> {
        if let failure = PortalPathRules.failure(of: path) { return .failure(failure) }
        let parts = path.split(separator: "/").map(String.init)
        guard let name = parts.last else { return .failure(.emptyPath) }
        if PortalFileTypes.fromExtension((name as NSString).pathExtension) != declaredType {
            return .failure(declaredType == .unknown ? .typeNotAllowed : .typeMismatch)
        }
        if case .failure = FlingNames.validate(name) { return .failure(.unsafeName) }
        let opened = PortalFileIO.open(parts)
        switch opened {
        case .failure(let error):
            return .failure(error)
        case .success(let file):
            defer { PortalFileIO.close(file.descriptor) }
            guard let info = PortalFileIO.status(file.descriptor) else { return .failure(.unresolved) }
            if let failure = PortalFileIO.admit(info) { return .failure(failure) }
            switch PortalFileIO.read(file.descriptor, expected: Int(info.st_size)) {
            case .failure(let error):
                return .failure(error)
            case .success(let bytes):
                return .success(PortalLoadedFile(displayName: name, bytes: bytes))
            }
        }
    }
}

public enum PortalInbox {
    /// Writes only a single path component inside `root`. The directory must be private to this user.
    public static func write(bytes: Data, fileName: String, root: String) -> Result<String, PortalDropFailure> {
        if fileName.isEmpty || fileName.contains("/") || fileName.contains("\\") || fileName.contains("\u{0}")
            || fileName == "." || fileName == ".." || fileName.hasPrefix(".") {
            return .failure(.unsafeName)
        }
        if case .failure = FlingNames.validate(fileName) { return .failure(.unsafeName) }
        if let failure = PortalPathRules.failure(of: root) { return .failure(failure == .emptyPath ? .insecureSandbox : failure) }
        let destination = root.hasSuffix("/") ? root + fileName : root + "/" + fileName
        guard PortalPathRules.isInside(destination, root: root) else { return .failure(.outputEscapesSandbox) }
        let parts = root.split(separator: "/").map(String.init)
        switch PortalFileIO.open(parts, directory: true) {
        case .failure(let error):
            return .failure(error == .symlink ? .symlink : .insecureSandbox)
        case .success(let folder):
            defer { PortalFileIO.close(folder.descriptor) }
            guard let info = PortalFileIO.status(folder.descriptor) else { return .failure(.insecureSandbox) }
            if !PortalFileIO.privateDirectory(info) { return .failure(.insecureSandbox) }
            return PortalFileIO.write(folder.descriptor, name: fileName, bytes: bytes).map { destination }
        }
    }
}

public enum PortalLocalConversion {
    public static func importDrop(path: String, declaredType: PortalFileType, inbox: String, codecs: PortalCodecs = .standard) -> PortalDropFlow {
        switch PortalExternalDrop.read(path: path, declaredType: declaredType) {
        case .failure(let error):
            var flow = PortalDropFlow()
            _ = flow.receive(.failure(error))
            return flow
        case .success(let loaded):
            let kind: PortalConversionKind = declaredType == .plainText ? .utf8Text : .png
            guard case .success = PortalOutputName.make(displayName: loaded.displayName, kind: kind) else {
                var flow = PortalDropFlow()
                _ = flow.receive(.failure(.unsafeName))
                return flow
            }
            let stored = inbox.hasSuffix("/") ? inbox + loaded.displayName : inbox + "/" + loaded.displayName
            let claim = PortalFileClaim(
                displayName: loaded.displayName,
                sandboxRoot: inbox,
                path: stored,
                canonicalPath: stored,
                isSymbolicLink: false,
                hasSymbolicLinkAncestor: false,
                isRegularFile: true,
                linkCount: 1,
                sizeBytes: Int64(loaded.bytes.count),
                declaredType: declaredType,
                ownerMatches: true
            )
            let converted = PortalDropSession.run(claim: .success(claim), bytes: loaded.bytes, codecs: codecs)
            guard case .done(let output) = converted.phase else { return converted }
            switch PortalInbox.write(bytes: output.bytes, fileName: output.fileName, root: inbox) {
            case .success:
                return converted
            case .failure(let error):
                var flow = PortalDropFlow()
                _ = flow.receive(.failure(error))
                return flow
            }
        }
    }
}

enum PortalFileIO {
    struct Opened { var descriptor: Int32 }

    static func close(_ descriptor: Int32) {
        #if canImport(Darwin)
        _ = Darwin.close(descriptor)
        #else
        _ = Glibc.close(descriptor)
        #endif
    }

    static func open(_ parts: [String], directory: Bool = false) -> Result<Opened, PortalDropFailure> {
        guard !parts.isEmpty else { return .failure(.emptyPath) }
        let parents = directory ? parts : Array(parts.dropLast())
        let leaf = directory ? nil : parts.last
        var current = systemOpen("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        if current < 0 { return .failure(.unresolved) }
        for name in parents {
            let next = openChild(current, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let code = errno
            close(current)
            // Linux reports a symlink opened with O_DIRECTORY|O_NOFOLLOW as ENOTDIR, not ELOOP.
            guard next >= 0 else { return .failure(mapDirectory(code)) }
            current = next
        }
        guard let leaf else { return .success(Opened(descriptor: current)) }
        let file = openChild(current, leaf, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        let code = errno
        close(current)
        guard file >= 0 else { return .failure(mapFile(code)) }
        return .success(Opened(descriptor: file))
    }

    static func status(_ descriptor: Int32) -> stat? {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return nil }
        return info
    }

    static func admit(_ info: stat) -> PortalDropFailure? {
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { return .notRegularFile }
        if info.st_nlink < 1 { return .notRegularFile }
        if info.st_nlink != 1 { return .hardLink }
        if info.st_uid != getuid() { return .wrongOwner }
        if info.st_size < 0 { return .unreadableSize }
        if info.st_size == 0 { return .empty }
        if info.st_size > Int64(PortalLimits.maxConversionBytes) { return .tooLarge }
        return nil
    }

    static func privateDirectory(_ info: stat) -> Bool {
        (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) && info.st_uid == getuid() && (info.st_mode & 0o077) == 0
    }

    static func read(_ descriptor: Int32, expected: Int) -> Result<Data, PortalDropFailure> {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let limit = PortalLimits.maxConversionBytes
        while data.count <= limit {
            let amount = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                #if canImport(Darwin)
                return Darwin.read(descriptor, base, raw.count)
                #else
                return Glibc.read(descriptor, base, raw.count)
                #endif
            }
            if amount < 0 {
                if errno == EINTR { continue }
                return .failure(.unresolved)
            }
            if amount == 0 { break }
            if data.count > limit - amount { return .failure(.tooLarge) }
            data.append(contentsOf: buffer.prefix(amount))
        }
        if data.count != expected { return .failure(.sizeMismatch) }
        return .success(data)
    }

    static func write(_ directory: Int32, name: String, bytes: Data) -> Result<Void, PortalDropFailure> {
        let flags = O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC
        let file = openChild(directory, name, flags, mode_t(0o600))
        guard file >= 0 else { return .failure(errno == ELOOP ? .symlink : .writeFailed) }
        defer { close(file) }
        var failed = false
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var cursor = base
            var left = raw.count
            while left > 0 {
                let wrote: Int
                #if canImport(Darwin)
                wrote = Darwin.write(file, cursor, left)
                #else
                wrote = Glibc.write(file, cursor, left)
                #endif
                if wrote < 0 {
                    if errno == EINTR { continue }
                    failed = true
                    return
                }
                cursor = cursor.advanced(by: wrote)
                left -= wrote
            }
        }
        if failed || fchmod(file, mode_t(0o600)) != 0 { return .failure(.writeFailed) }
        return .success(())
    }

    private static func openChild(_ directory: Int32, _ name: String, _ flags: Int32, _ mode: mode_t = 0) -> Int32 {
        name.withCString { openat(directory, $0, flags, mode) }
    }

    private static func systemOpen(_ path: String, _ flags: Int32) -> Int32 {
        path.withCString { pointer in
            #if canImport(Darwin)
            Darwin.open(pointer, flags)
            #else
            Glibc.open(pointer, flags)
            #endif
        }
    }

    private static func mapDirectory(_ code: Int32) -> PortalDropFailure {
        switch code {
        case ELOOP, ENOTDIR: .symlink
        case ENOENT: .unresolved
        default: .unresolved
        }
    }

    private static func mapFile(_ code: Int32) -> PortalDropFailure {
        switch code {
        case ELOOP: .symlink
        case ENOENT: .unresolved
        case ENOTDIR: .notRegularFile
        default: .unresolved
        }
    }
}
