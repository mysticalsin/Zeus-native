import Foundation
#if os(macOS)
import os
#endif

/// The only log for this path. Secrets are replaced before the line reaches the sink.
/// Spoken text is not a log field. Do not pass a response body: a vendor can echo a key.
public struct ProviderLog: Sendable {
    public var sink: @Sendable (String) -> Void

    public init(sink: @escaping @Sendable (String) -> Void = { _ in }) {
        self.sink = sink
    }

    public func record(_ line: String, secrets: [String] = []) {
        var safe = line.replacingOccurrences(of: "\n", with: " ")
        for secret in secrets {
            let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 4 else { continue }
            safe = safe.replacingOccurrences(of: trimmed, with: "••••")
            if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .alphanumerics), encoded != trimmed {
                safe = safe.replacingOccurrences(of: encoded, with: "••••")
            }
        }
        sink(safe)
    }
}

public enum ProviderSignpostName {
    public static let firstAudio = "voice.first-audio"
}

public struct ProviderSignpostSample: Equatable, Sendable {
    public var name: String
    public var milliseconds: Int
    public var metadata: [String: String]
    public init(name: String, milliseconds: Int, metadata: [String: String]) {
        self.name = name
        self.milliseconds = milliseconds
        self.metadata = metadata
    }
}

/// Records `voice.first-audio`. Metadata keeps only a provider id and a route.
/// On macOS the same interval is an `OSSignposter` interval. Linux records the sample only.
public final class ProviderSignposter: @unchecked Sendable {
    /// A long session keeps the latest marks, not every mark since launch.
    public static let sampleCap = 64
    private let lock = NSLock()
    public private(set) var samples: [ProviderSignpostSample] = []

    public init() {}

    public func begin() -> ProviderSignpostInterval {
        #if os(macOS)
        let poster = OSSignposter(subsystem: "app.zeus.voice", category: "provider")
        let state = poster.beginInterval("voice.first-audio", id: .exclusive)
        return ProviderSignpostInterval(started: ContinuousClock.now, poster: poster, state: state)
        #else
        return ProviderSignpostInterval(started: ContinuousClock.now)
        #endif
    }

    @discardableResult
    public func end(_ interval: ProviderSignpostInterval, metadata: [String: String]) -> Int {
        let milliseconds = ProviderClock.milliseconds(since: interval.started)
        #if os(macOS)
        interval.poster.endInterval("voice.first-audio", interval.state)
        #endif
        let sample = ProviderSignpostSample(name: ProviderSignpostName.firstAudio, milliseconds: milliseconds, metadata: Self.sanitize(metadata))
        lock.lock()
        samples.append(sample)
        if samples.count > Self.sampleCap {
            samples.removeFirst(samples.count - Self.sampleCap)
        }
        lock.unlock()
        return milliseconds
    }

    static func sanitize(_ metadata: [String: String]) -> [String: String] {
        var kept: [String: String] = [:]
        for key in ["provider", "route"] {
            guard let value = metadata[key], value.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil else { continue }
            kept[key] = value
        }
        return kept
    }
}

public struct ProviderSignpostInterval: @unchecked Sendable {
    var started: ContinuousClock.Instant
    #if os(macOS)
    var poster: OSSignposter
    var state: OSSignpostIntervalState
    #endif
}

enum ProviderClock {
    static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let (seconds, attoseconds) = start.duration(to: .now).components
        let milliseconds = (Int(seconds) * 1_000) + Int(attoseconds / 1_000_000_000_000_000)
        return max(0, milliseconds)
    }
}
