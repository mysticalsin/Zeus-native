import Foundation

// Ported from github.com/mysticalsin/jarvis2.0
// Source paths: frontend/src/voice.ts (playback analyser) and frontend/src/orb.ts (band sums)
// Source commit: 16e37bd801eb797798e02540665f8b3804b0fe14
// Copyright (c) 2026 Ethan Rogers
// License: personal non-commercial grant. Full text: LICENSES/jarvis2.0-LICENSE

/// Bass and mid in 0...1, the range `frontend/src/orb.ts:173-175` reads from the analyser.
public struct OrbAudioBands: Equatable, Sendable {
    public var bass: Double
    public var mid: Double

    public init(bass: Double, mid: Double) {
        self.bass = bass
        self.mid = mid
    }

    public static let silent = OrbAudioBands(bass: 0, mid: 0)

    /// The analyser only emits 0...1. Non-finite or out-of-range input from a caller becomes that range
    /// so a bad tap cannot push particle positions to infinity.
    public static func sanitized(_ bass: Double, _ mid: Double) -> OrbAudioBands {
        OrbAudioBands(bass: unit(bass), mid: unit(mid))
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

public protocol PlaybackBandProviding: Sendable {
    func playbackBands() -> OrbAudioBands
}

/// `voice.ts:497-498` fftSize 256 and smoothingTimeConstant 0.8.
/// `orb.ts:173-175` averages bins 0..<8 and 8..<24, then divides by 255.
public enum OrbAnalyser {
    public static let fftSize = 256
    public static let smoothing = 0.8

    public static func rawBands(samples: [Float], sampleRate: Double) -> OrbAudioBands {
        guard sampleRate > 0, !samples.isEmpty else { return .silent }
        let count = min(fftSize, samples.count)
        let start = samples.count - count
        var bass = 0.0
        var mid = 0.0
        for bin in 0..<8 { bass += magnitude(samples: samples, start: start, count: count, bin: bin) }
        for bin in 8..<24 { mid += magnitude(samples: samples, start: start, count: count, bin: bin) }
        return OrbAudioBands(bass: min(bass / 8, 1), mid: min(mid / 16, 1))
    }

    public static func smoothed(samples: [Float], sampleRate: Double, previous: OrbAudioBands) -> OrbAudioBands {
        let raw = rawBands(samples: samples, sampleRate: sampleRate)
        return OrbAudioBands(
            bass: smoothing * previous.bass + (1 - smoothing) * raw.bass,
            mid: smoothing * previous.mid + (1 - smoothing) * raw.mid)
    }

    private static func magnitude(samples: [Float], start: Int, count: Int, bin: Int) -> Double {
        var real = 0.0
        var imag = 0.0
        let n = Double(count)
        for offset in 0..<count {
            let angle = 2 * Double.pi * Double(bin) * Double(offset) / n
            let sample = Double(samples[start + offset])
            real += sample * cos(angle)
            imag -= sample * sin(angle)
        }
        return (real * real + imag * imag).squareRoot() / (n / 2)
    }
}

/// Latest playback bands. The voice stack is unchanged; a caller may publish samples into this meter.
public final class OrbPlaybackMeter: PlaybackBandProviding, @unchecked Sendable {
    public static let shared = OrbPlaybackMeter()

    private let lock = NSLock()
    private var latest = OrbAudioBands.silent

    public func playbackBands() -> OrbAudioBands {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    public func ingest(samples: [Float], sampleRate: Double) {
        lock.lock()
        let previous = latest
        lock.unlock()
        let next = OrbAnalyser.smoothed(samples: samples, sampleRate: sampleRate, previous: previous)
        lock.lock()
        latest = next
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        latest = .silent
        lock.unlock()
    }
}
