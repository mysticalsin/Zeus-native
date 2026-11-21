import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Dev-only character meter for opted-in cloud voices. The count is stored per provider in
/// Application Support. It is not a key, and this file never contains one.
///
/// A request that would make the stored total reach 50,000 characters is refused, and the stored
/// total is left unchanged. Unreadable or non-integral state fails closed: the request is not sent
/// and the file is not rewritten.
public final class VoiceQualityMeter: @unchecked Sendable {
    public static let limit = 50_000
    public static let fileName = "voice-quality-meter.json"
    /// A tampered meter file larger than this is unreadable. Counts for two providers fit easily.
    static let maxFileBytes = 65_536

    private let lock = NSLock()
    private let fileURL: URL

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(Self.fileName)
    }

    /// The meter file under Application Support/Zeus. Tests pass their own directory.
    public static func applicationSupport() throws -> VoiceQualityMeter {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try VoiceQualityMeter(directory: base.appendingPathComponent("Zeus", isDirectory: true))
    }

    public func count(providerID: String) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return try load()[providerID] ?? 0
    }

    /// Counts `characters` before the request is sent. `characters` is the sanitized text length.
    public func reserve(providerID: String, characters: Int) throws {
        lock.lock(); defer { lock.unlock() }
        guard characters >= 0 else { throw VoiceQualityError.meterCorrupt }
        let counts = try load()
        guard characters > 0 else { return }
        let used = counts[providerID] ?? 0
        let total = used + characters
        guard total < Self.limit else { throw VoiceQualityError.meterExceeded }
        var updated = counts
        updated[providerID] = total
        try store(updated)
    }

    private func load() throws -> [String: Int] {
        let data: Data
        do {
            guard let read = try Self.readNoFollow(fileURL) else { return [:] }
            data = read
        } catch {
            throw VoiceQualityError.meterCorrupt
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VoiceQualityError.meterCorrupt
        }
        var counts: [String: Int] = [:]
        for (key, value) in json {
            guard let whole = Self.whole(value) else { throw VoiceQualityError.meterCorrupt }
            counts[key] = whole
        }
        return counts
    }

    private func store(_ counts: [String: Int]) throws {
        let data: Data
        do { data = try JSONSerialization.data(withJSONObject: counts, options: [.sortedKeys]) }
        catch { throw VoiceQualityError.meterCorrupt }
        guard data.count <= Self.maxFileBytes else { throw VoiceQualityError.meterCorrupt }
        try Self.refuseSymlink(fileURL)
        let temporary = fileURL.deletingLastPathComponent().appendingPathComponent(".voice-quality-meter-\(UUID().uuidString).tmp")
        do { try Self.writeNoFollow(data, to: temporary) }
        catch {
            unlink(temporary.path)
            throw VoiceQualityError.meterCorrupt
        }
        if rename(temporary.path, fileURL.path) != 0 {
            unlink(temporary.path)
            throw VoiceQualityError.meterCorrupt
        }
    }

    /// `O_NOFOLLOW` so a swapped symlink is an error, not a read or write of another file.
    private static func readNoFollow(_ url: URL) throws -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw VoiceQualityError.meterCorrupt
        }
        defer { close(fd) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return read(fd, base, raw.count)
            }
            if count == 0 { break }
            if count < 0 { throw VoiceQualityError.meterCorrupt }
            data.append(contentsOf: buffer.prefix(count))
            if data.count > maxFileBytes { throw VoiceQualityError.meterCorrupt }
        }
        return data
    }

    private static func refuseSymlink(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return }
            throw VoiceQualityError.meterCorrupt
        }
        close(fd)
    }

    private static func writeNoFollow(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        if fd < 0 { throw VoiceQualityError.meterCorrupt }
        var failed = false
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = raw.baseAddress.map { base in
                    write(fd, base.advanced(by: offset), raw.count - offset)
                } ?? -1
                if count < 0 { failed = true; break }
                offset += count
            }
        }
        close(fd)
        if failed { throw VoiceQualityError.meterCorrupt }
    }

    private static func whole(_ value: Any) -> Int? {
        if value is Bool { return nil }
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double >= 0, double <= Double(Int.max), double.rounded(.towardZero) == double else { return nil }
        return Int(double)
    }
}
