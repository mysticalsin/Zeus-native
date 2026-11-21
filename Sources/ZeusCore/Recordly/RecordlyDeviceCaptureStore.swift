import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum RecordlyDeviceCaptureWriteError: Equatable, Error, Sendable {
    case diskFull
    case permissionDenied(RecordlyDeviceCaptureDevice)
    case failed(String)

    /// `640` is `NSFileWriteOutOfSpaceError`. `-11813` is `AVError.diskFull`.
    public static func classify(domain: String, code: Int) -> RecordlyDeviceCaptureWriteError? {
        if domain == "NSPOSIXErrorDomain", code == Int(ENOSPC) || code == Int(EDQUOT) {
            return .diskFull
        }
        if domain == "NSCocoaErrorDomain", code == 640 { return .diskFull }
        if domain == "AVFoundationErrorDomain", code == -11813 { return .diskFull }
        return nil
    }
}

/// Local Recordly microphone and camera files. They stay in Zeus's support directory, mode 0600.
/// Nothing here opens a network connection.
public enum RecordlyDeviceCaptureStore {
    public static let reserveBytes: Int64 = 1_048_576

    public static func fileName(for selection: RecordlyDeviceCaptureSelection, at date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(
            format: "%04d%02d%02d-%02d%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
        let kind: String
        let ext: String
        switch (selection.microphone, selection.camera) {
        case (true, true):
            kind = "microphone-camera"
            ext = "mov"
        case (false, true):
            kind = "camera"
            ext = "mov"
        default:
            kind = "microphone"
            ext = "m4a"
        }
        return "recordly-\(kind)-\(stamp).\(ext)"
    }

    public static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 120, name != ".", name != ".." else { return false }
        guard !name.hasPrefix(".") else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7f && scalar != "/" && scalar != "\\"
        }
    }

    /// Creates `Recordly` under the support directory when there is room. A short volume refuses before any file exists.
    public static func prepareDirectory(supportDirectory: URL, reserveBytes: Int64) throws -> URL {
        let directory = supportDirectory.appendingPathComponent("Recordly", isDirectory: true)
        let free = freeBytes(forSupport: supportDirectory)
        if free >= 0, free < reserveBytes {
            throw RecordlyDeviceCaptureWriteError.diskFull
        }
        try makePrivateDirectory(directory)
        return directory
    }

    public static func freeBytes(forSupport supportDirectory: URL) -> Int64 {
        var stats = statvfs()
        if statvfs(supportDirectory.path, &stats) != 0 {
            let parent = supportDirectory.deletingLastPathComponent()
            if statvfs(parent.path, &stats) != 0 { return -1 }
        }
        return Int64(stats.f_bavail) * Int64(stats.f_frsize)
    }

    public static func save(
        data: Data,
        fileName: String,
        supportDirectory: URL,
        freeBytes: (URL) -> Int64,
        simulatedPOSIXError: Int32? = nil
    ) throws -> RecordlyDeviceCaptureReceipt {
        guard isSafeFileName(fileName) else {
            throw RecordlyDeviceCaptureWriteError.failed("The recording name is not safe.")
        }
        let directory = supportDirectory.appendingPathComponent("Recordly", isDirectory: true)
        let available = freeBytes(directory)
        if available >= 0, Int64(data.count) > available {
            throw RecordlyDeviceCaptureWriteError.diskFull
        }
        try makePrivateDirectory(directory)
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        if fd < 0 {
            if errno == ENOSPC || errno == EDQUOT {
                throw RecordlyDeviceCaptureWriteError.diskFull
            }
            throw RecordlyDeviceCaptureWriteError.failed("The recording could not be created.")
        }
        if let simulatedPOSIXError {
            _ = close(fd)
            _ = unlink(url.path)
            if simulatedPOSIXError == ENOSPC || simulatedPOSIXError == EDQUOT {
                throw RecordlyDeviceCaptureWriteError.diskFull
            }
            throw RecordlyDeviceCaptureWriteError.failed("The recording could not be written.")
        }
        do {
            try writeAll(fd: fd, data: data)
        } catch {
            _ = close(fd)
            _ = unlink(url.path)
            throw error
        }
        if fchmod(fd, 0o600) != 0 {
            _ = close(fd)
            _ = unlink(url.path)
            throw RecordlyDeviceCaptureWriteError.failed("The recording could not be made private.")
        }
        _ = close(fd)
        return try receipt(for: url, byteCount: data.count)
    }

    /// Narrows a file the capture engine already wrote. Refuses anything that is not owner-read/write.
    public static func protect(_ url: URL) throws -> RecordlyDeviceCaptureReceipt {
        guard url.isFileURL else {
            throw RecordlyDeviceCaptureWriteError.failed("The recording could not be kept private.")
        }
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw RecordlyDeviceCaptureWriteError.failed("The recording could not be kept private.")
        }
        if chmod(url.path, 0o600) != 0 {
            _ = unlink(url.path)
            throw RecordlyDeviceCaptureWriteError.failed("The recording could not be made private.")
        }
        return try receipt(for: url, byteCount: Int(info.st_size))
    }

    private static func makePrivateDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        if chmod(directory.path, 0o700) != 0 {
            throw RecordlyDeviceCaptureWriteError.failed("The recordings folder could not be made private.")
        }
        var info = stat()
        guard lstat(directory.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == getuid()
        else {
            throw RecordlyDeviceCaptureWriteError.failed("The recordings folder is not a private folder owned by you.")
        }
    }

    private static func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else {
                if data.isEmpty { return }
                throw RecordlyDeviceCaptureWriteError.failed("The recording could not be written.")
            }
            var offset = 0
            while offset < buffer.count {
                let amount = write(fd, base.advanced(by: offset), buffer.count - offset)
                if amount < 0, errno == EINTR { continue }
                if amount < 0 {
                    let code = errno
                    if code == ENOSPC || code == EDQUOT {
                        throw RecordlyDeviceCaptureWriteError.diskFull
                    }
                    throw RecordlyDeviceCaptureWriteError.failed("The recording could not be written.")
                }
                guard amount > 0 else {
                    throw RecordlyDeviceCaptureWriteError.failed("The recording could not be written.")
                }
                offset += amount
            }
        }
    }

    private static func receipt(for url: URL, byteCount: Int) throws -> RecordlyDeviceCaptureReceipt {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let mode = ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777
        guard mode == 0o600 else {
            _ = unlink(url.path)
            throw RecordlyDeviceCaptureWriteError.failed("The recording could not be kept private, so it was not saved.")
        }
        return RecordlyDeviceCaptureReceipt(url: url, byteCount: byteCount, mode: mode, uploaded: false)
    }
}
