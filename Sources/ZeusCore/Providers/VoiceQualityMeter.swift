import Foundation

/// Dev-only character meter for opted-in cloud voices. The count is stored per provider in
/// Application Support. It is not a key, and this file never contains one.
///
/// A request that would make the stored total reach 50,000 characters is refused, and the stored
/// total is left unchanged. Unreadable or non-integral state fails closed: the request is not sent
/// and the file is not rewritten.
public final class VoiceQualityMeter: @unchecked Sendable {
    public static let limit = 50_000
    public static let fileName = "voice-quality-meter.json"

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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data: Data
        do { data = try Data(contentsOf: fileURL) } catch { throw VoiceQualityError.meterCorrupt }
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
        do {
            let data = try JSONSerialization.data(withJSONObject: counts, options: [.sortedKeys])
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw VoiceQualityError.meterCorrupt
        }
    }

    private static func whole(_ value: Any) -> Int? {
        if value is Bool { return nil }
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double >= 0, double <= Double(Int.max), double.rounded(.towardZero) == double else { return nil }
        return Int(double)
    }
}
