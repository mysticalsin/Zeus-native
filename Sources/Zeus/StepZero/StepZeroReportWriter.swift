import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Writes one step-zero report beside the other files the caller already owns.
///
/// The folder is a real directory owned by this user, mode 0700. A missing folder is created
/// at that mode. A link, a different owner, or any other mode is left untouched and nothing is
/// written. The file is created with `O_CREAT`, `O_EXCL` and `O_NOFOLLOW` at mode 0600, so a
/// name that already exists, including a link, is not replaced. A failed write removes the file
/// it just created. The digest is the lowercase SHA-256 of the bytes. The screen shows the
/// first 16 digits of that digest.
public enum StepZeroReportWriter {
    public static let folderMode = 0o700
    public static let fileMode = 0o600
    /// The codec refuses a report larger than this, so the writer does not create one.
    public static let byteLimit = 256 * 1024
    public static let screenDigits = 16

    public struct PathFacts: Equatable, Sendable {
        public var exists: Bool
        public var isSymbolicLink: Bool
        public var isDirectory: Bool
        public var isRegularFile: Bool
        public var ownerIsCaller: Bool
        public var permissions: Int

        public init(
            exists: Bool,
            isSymbolicLink: Bool,
            isDirectory: Bool,
            isRegularFile: Bool,
            ownerIsCaller: Bool,
            permissions: Int
        ) {
            self.exists = exists
            self.isSymbolicLink = isSymbolicLink
            self.isDirectory = isDirectory
            self.isRegularFile = isRegularFile
            self.ownerIsCaller = ownerIsCaller
            self.permissions = permissions
        }
    }

    public enum FolderRuling: Equatable, Sendable {
        case make
        case open
        case refuse
    }

    public enum Refusal: Equatable, Sendable {
        case name
        case folder
        case link
        case existing
        case tooLarge
        case write
    }

    public enum Outcome: Equatable, Sendable {
        case wrote(digest: String)
        case refused(Refusal)
    }

    /// Missing path: make it. A real directory this user owns at mode 0700: open it. Anything else: refuse.
    public static func rule(_ facts: PathFacts) -> FolderRuling {
        if !facts.exists { return .make }
        if facts.isSymbolicLink || !facts.isDirectory || !facts.ownerIsCaller || facts.permissions != folderMode {
            return .refuse
        }
        return .open
    }

    /// First 16 digits, only when `digest` is 64 lowercase hex digits.
    public static func screenDigest(_ digest: String) -> String? {
        guard digest.utf8.count == 64 else { return nil }
        let hex = digest.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x61 && byte <= 0x66)
        }
        guard hex else { return nil }
        return String(digest.prefix(screenDigits))
    }

    public static func facts(at url: URL) -> PathFacts {
        var info = pathStatus()
        let ok = url.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else { return false }
            return lstat(pointer, &info) == 0
        }
        guard ok else {
            return PathFacts(
                exists: false, isSymbolicLink: false, isDirectory: false,
                isRegularFile: false, ownerIsCaller: false, permissions: 0
            )
        }
        let mode = UInt32(info.st_mode)
        let kind = mode & 0o170000
        return PathFacts(
            exists: true,
            isSymbolicLink: kind == 0o120000,
            isDirectory: kind == 0o040000,
            isRegularFile: kind == 0o100000,
            ownerIsCaller: info.st_uid == getuid(),
            permissions: Int(mode & 0o777)
        )
    }

    public static func write(_ bytes: Data, into directory: URL, named name: String) -> Outcome {
        write(bytes, into: directory, named: name, transfer: writeAll)
    }

    public static func write(
        _ bytes: Data,
        into directory: URL,
        named name: String,
        transfer: @Sendable (Int32, Data) -> Bool
    ) -> Outcome {
        guard nameIsOneComponent(name) else { return .refused(.name) }
        guard bytes.count <= byteLimit else { return .refused(.tooLarge) }
        guard !directory.path.isEmpty else { return .refused(.folder) }

        let looked = facts(at: directory)
        switch rule(looked) {
        case .refuse:
            return .refused(.folder)
        case .make:
            guard makeFolder(directory) else { return .refused(.folder) }
        case .open:
            break
        }

        let file = directory.appendingPathComponent(name, isDirectory: false)
        let opened = openNewFile(file)
        switch opened {
        case .failure(let refusal):
            return .refused(refusal)
        case .success(let fd):
            let stored = transfer(fd, bytes)
            let sealed = stored && fchmod(fd, mode_t(fileMode)) == 0 && fsync(fd) == 0
            let closed = close(fd)
            if !sealed || closed != 0 {
                unlinkPath(file)
                return .refused(.write)
            }
            let digest = StepZeroDigest.hex(bytes)
            guard screenDigest(digest) != nil else {
                unlinkPath(file)
                return .refused(.write)
            }
            return .wrote(digest: digest)
        }
    }

    /// Writes every byte, retrying an interrupted call. False leaves the caller to remove the file.
    public static func writeAll(_ fd: Int32, _ bytes: Data) -> Bool {
        if bytes.isEmpty { return true }
        var offset = 0
        let total = bytes.count
        return bytes.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            while offset < total {
                let wrote = systemWrite(fd, base.advanced(by: offset), total - offset)
                if wrote < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                if wrote == 0 { return false }
                offset += wrote
            }
            return true
        }
    }

    private static func nameIsOneComponent(_ name: String) -> Bool {
        if name.isEmpty || name == "." || name == ".." { return false }
        if name.utf8.count > 255 { return false }
        if name.utf8.contains(0) || name.contains("/") { return false }
        return true
    }

    private static func makeFolder(_ directory: URL) -> Bool {
        let created = directory.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else { return false }
            return mkdir(pointer, mode_t(folderMode)) == 0
        }
        if created {
            guard lockFolder(directory), rule(facts(at: directory)) == .open else {
                removeFolder(directory)
                return false
            }
            return true
        }
        return rule(facts(at: directory)) == .open
    }

    private static func lockFolder(_ directory: URL) -> Bool {
        let fd = directory.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return open(pointer, directoryOpenFlags, 0)
        }
        guard fd >= 0 else { return false }
        let changed = fchmod(fd, mode_t(folderMode)) == 0
        let closed = close(fd) == 0
        return changed && closed
    }

    private enum Opened {
        case success(Int32)
        case failure(Refusal)
    }

    private static func openNewFile(_ file: URL) -> Opened {
        let fd = file.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return open(pointer, fileOpenFlags, mode_t(fileMode))
        }
        if fd >= 0 { return .success(fd) }
        let error = errno
        let found = facts(at: file)
        if found.isSymbolicLink { return .failure(.link) }
        if found.exists { return .failure(.existing) }
        if error == EEXIST || error == ELOOP { return .failure(.existing) }
        return .failure(.write)
    }

    private static func unlinkPath(_ file: URL) {
        _ = file.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return unlink(pointer)
        }
    }

    private static func removeFolder(_ directory: URL) {
        _ = directory.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return rmdir(pointer)
        }
    }
}

private let fileOpenFlags = O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY | O_CLOEXEC
#if canImport(Glibc)
private let directoryOpenFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
#else
private let directoryOpenFlags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC
#endif

private func pathStatus() -> stat {
    stat()
}

private func systemWrite(_ fd: Int32, _ buffer: UnsafePointer<UInt8>, _ count: Int) -> Int {
    write(fd, buffer, count)
}

/// SHA-256, so the digest can be checked with `shasum -a 256` on either platform.
enum StepZeroDigest {
    static func hex(_ data: Data) -> String {
        var hash: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        var message = [UInt8](data)
        let bitCount = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitCount >> UInt64(shift)) & 0xff))
        }
        var block = 0
        while block < message.count {
            var word = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let start = block + index * 4
                word[index] = (UInt32(message[start]) << 24)
                    | (UInt32(message[start + 1]) << 16)
                    | (UInt32(message[start + 2]) << 8)
                    | UInt32(message[start + 3])
            }
            for index in 16..<64 {
                let older = word[index - 15]
                let newer = word[index - 2]
                let small = rotate(older, 7) ^ rotate(older, 18) ^ (older >> 3)
                let large = rotate(newer, 17) ^ rotate(newer, 19) ^ (newer >> 10)
                word[index] = word[index - 16] &+ small &+ word[index - 7] &+ large
            }
            var a = hash[0], b = hash[1], c = hash[2], d = hash[3]
            var e = hash[4], f = hash[5], g = hash[6], h = hash[7]
            for index in 0..<64 {
                let sum1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
                let choose = (e & f) ^ (~e & g)
                let first = h &+ sum1 &+ choose &+ roundConstant[index] &+ word[index]
                let sum0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let second = sum0 &+ majority
                h = g
                g = f
                f = e
                e = d &+ first
                d = c
                c = b
                b = a
                a = first &+ second
            }
            hash[0] = hash[0] &+ a
            hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c
            hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e
            hash[5] = hash[5] &+ f
            hash[6] = hash[6] &+ g
            hash[7] = hash[7] &+ h
            block += 64
        }
        return hash.map { value in
            (0..<4).reversed().map { shift in
                String(format: "%02x", UInt8((value >> (shift * 8)) & 0xff))
            }.joined()
        }.joined()
    }

    private static func rotate(_ value: UInt32, _ places: UInt32) -> UInt32 {
        (value >> places) | (value << (32 - places))
    }

    private static let roundConstant: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]
}
