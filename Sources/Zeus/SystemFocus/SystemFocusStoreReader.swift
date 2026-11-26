import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Lowest layer of the Focus store read. Opens one folder, then the two store
/// files relative to that descriptor. A stamp match reads nothing. Bytes over
/// the cap are dropped. This file keeps no Focus name, parses nothing, and
/// writes nothing. The folder name lives only here.
public struct SystemFocusStoreReader: Sendable {
    public static let maxBytes = 4 * 1024 * 1024
    public static let assertionsFileName = "Assertions.json"
    public static let configurationsFileName = "ModeConfigurations.json"
    /// `~/Library/<storeDirectory>/<storeLeaf>`.
    public static let storeDirectory = "DoNotDisturb"
    public static let storeLeaf = "DB"

    private static let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    private static let fileFlags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC

    private init() {}

    /// Inode, size, and modification time, plus the device so a replaced file is not equal.
    public struct Stamp: Equatable, Sendable {
        public var device: UInt64
        public var inode: UInt64
        public var size: Int64
        public var seconds: Int64
        public var nanoseconds: Int64

        public init(device: UInt64, inode: UInt64, size: Int64, seconds: Int64, nanoseconds: Int64) {
            self.device = device
            self.inode = inode
            self.size = size
            self.seconds = seconds
            self.nanoseconds = nanoseconds
        }
    }

    public struct Stamps: Equatable, Sendable {
        public var assertions: Stamp?
        public var configurations: Stamp?

        public init(assertions: Stamp? = nil, configurations: Stamp? = nil) {
            self.assertions = assertions
            self.configurations = configurations
        }
    }

    /// One file after a bounded read. `.bytes` is the only case that holds data.
    public enum FileBody: Equatable, Sendable {
        case bytes(Data)
        case missing
        case denied
        case notAFile
        case tooLarge
        case other
    }

    public enum FolderFault: Equatable, Sendable {
        case missing
        case denied
        case notAFile
        case other
    }

    public enum Read: Equatable, Sendable {
        case opened(assertions: FileBody, configurations: FileBody, stamps: Stamps)
        case unchanged(Stamps)
        case folder(FolderFault)
    }

    /// Joins the account home to the store folder. Does not open it.
    /// An empty home, or a home that contains NUL or a newline, is nil.
    public static func folder(home: String) -> String? {
        guard !home.isEmpty, !home.contains("\0"), !home.contains("\n") else { return nil }
        let root = home == "/" ? "" : (home.hasSuffix("/") ? String(home.dropLast()) : home)
        guard home == "/" || !root.isEmpty else { return nil }
        return root + "/Library/" + storeDirectory + "/" + storeLeaf
    }

    /// The account home from the user record, not from the environment. Does not open the folder.
    public static func liveFolder() -> String? {
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else { return nil }
        return folder(home: String(cString: home))
    }

    /// `EPERM` and `EACCES` are denied. `ENOENT` is missing. `ENOTDIR` and `ELOOP` are not a file.
    public static func classify(errno code: Int32) -> FolderFault {
        switch code {
        case EPERM, EACCES: return .denied
        case ENOENT: return .missing
        case ENOTDIR, ELOOP: return .notAFile
        default: return .other
        }
    }

    /// Opens `folder` read-only and no-follow. `previous` skips the read when both stamps still match.
    /// `chunkBytes` is only the read size. A value below 1 reads one byte at a time.
    public static func read(folder path: String, ifChangedFrom previous: Stamps? = nil, chunkBytes: Int = 16_384) -> Read {
        guard !path.isEmpty, !path.contains("\0") else { return .folder(.other) }
        let chunk = min(max(chunkBytes, 1), maxBytes + 1)
        let descriptor = path.withCString { open($0, directoryFlags) }
        guard descriptor >= 0 else { return .folder(classify(errno: errno)) }
        defer { _ = close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return .folder(.other) }
        guard kind(info.st_mode) == mode_t(S_IFDIR) else { return .folder(.notAFile) }

        let assertions = look(folder: descriptor, name: assertionsFileName)
        let configurations = look(folder: descriptor, name: configurationsFileName)
        let stamps = Stamps(assertions: assertions.stamp, configurations: configurations.stamp)
        if let previous, previous == stamps { return .unchanged(stamps) }
        return .opened(
            assertions: body(of: assertions, folder: descriptor, name: assertionsFileName, chunk: chunk),
            configurations: body(of: configurations, folder: descriptor, name: configurationsFileName, chunk: chunk),
            stamps: stamps
        )
    }

    private struct Look {
        var terminal: FileBody?
        var stamp: Stamp?
    }

    private static func look(folder: Int32, name: String) -> Look {
        var info = stat()
        let result = name.withCString { fstatat(folder, $0, &info, AT_SYMLINK_NOFOLLOW) }
        guard result == 0 else {
            let fault = classify(errno: errno)
            return Look(terminal: fileBody(fault), stamp: nil)
        }
        let stamp = stamp(of: info)
        let mode = kind(info.st_mode)
        guard mode == mode_t(S_IFREG) else { return Look(terminal: .notAFile, stamp: stamp) }
        guard info.st_size >= 0 else { return Look(terminal: .other, stamp: stamp) }
        guard info.st_size <= maxBytes else { return Look(terminal: .tooLarge, stamp: stamp) }
        return Look(terminal: nil, stamp: stamp)
    }

    private static func body(of look: Look, folder: Int32, name: String, chunk: Int) -> FileBody {
        if let terminal = look.terminal { return terminal }
        let file = name.withCString { openat(folder, $0, fileFlags) }
        guard file >= 0 else { return fileBody(classify(errno: errno)) }
        defer { _ = close(file) }
        var info = stat()
        guard fstat(file, &info) == 0 else { return .other }
        guard kind(info.st_mode) == mode_t(S_IFREG), info.st_size >= 0, info.st_size <= maxBytes else {
            return info.st_size > maxBytes ? .tooLarge : .notAFile
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: chunk)
        while true {
            let amount = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                #if canImport(Darwin)
                return Darwin.read(file, base, raw.count)
                #else
                return Glibc.read(file, base, raw.count)
                #endif
            }
            if amount < 0, errno == EINTR { continue }
            if amount < 0 { return .other }
            if amount == 0 { break }
            if data.count > maxBytes - amount { return .tooLarge }
            data.append(contentsOf: buffer.prefix(amount))
        }
        return .bytes(data)
    }

    private static func fileBody(_ fault: FolderFault) -> FileBody {
        switch fault {
        case .missing: return .missing
        case .denied: return .denied
        case .notAFile: return .notAFile
        case .other: return .other
        }
    }

    private static func kind(_ mode: mode_t) -> mode_t { mode & mode_t(S_IFMT) }

    private static func stamp(of info: stat) -> Stamp {
        let seconds: Int64
        let nanoseconds: Int64
        #if canImport(Darwin)
        seconds = Int64(info.st_mtimespec.tv_sec)
        nanoseconds = Int64(info.st_mtimespec.tv_nsec)
        #else
        seconds = Int64(info.st_mtim.tv_sec)
        nanoseconds = Int64(info.st_mtim.tv_nsec)
        #endif
        return Stamp(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            size: Int64(info.st_size),
            seconds: seconds,
            nanoseconds: nanoseconds
        )
    }
}
