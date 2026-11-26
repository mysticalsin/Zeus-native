import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Original lock and wake tones, written as samples. No audio file is read or bundled.
public enum ChimeTone {
    public static let sampleRate: Double = 44_100
    public static let maximumDuration: Double = 0.6

    public static func samples(for event: ChimeEvent) -> [Float] {
        switch event {
        case .open:
            // A soft two-note rise: F4, then C5.
            let first = tone(frequency: 349.23, seconds: 0.26, peak: 0.22, fadeIn: 0.030, fadeOut: 0.050)
            let second = tone(frequency: 523.25, seconds: 0.28, peak: 0.24, fadeIn: 0.030, fadeOut: 0.080)
            return mix(first, second, overlap: frames(0.040))
        case .close:
            // A soft fall from B4 down to D4.
            return glide(from: 493.88, to: 293.66, seconds: 0.48, peak: 0.26, fadeIn: 0.025, fadeOut: 0.090)
        }
    }

    private static func frames(_ seconds: Double) -> Int {
        Int((seconds * sampleRate).rounded())
    }

    private static func tone(frequency: Double, seconds: Double, peak: Double, fadeIn: Double, fadeOut: Double) -> [Float] {
        render(count: frames(seconds), fadeIn: frames(fadeIn), fadeOut: frames(fadeOut), peak: peak) { index, count in
            let time = Double(index) / sampleRate
            return sin(2 * .pi * frequency * time)
        }
    }

    private static func glide(from start: Double, to end: Double, seconds: Double, peak: Double, fadeIn: Double, fadeOut: Double) -> [Float] {
        let count = frames(seconds)
        var phase = 0.0
        return render(count: count, fadeIn: frames(fadeIn), fadeOut: frames(fadeOut), peak: peak) { index, total in
            let fraction = total <= 1 ? 0 : Double(index) / Double(total - 1)
            let frequency = start + (end - start) * fraction
            let sample = sin(phase)
            phase += 2 * .pi * frequency / sampleRate
            return sample
        }
    }

    private static func render(count: Int, fadeIn: Int, fadeOut: Int, peak: Double, wave: (Int, Int) -> Double) -> [Float] {
        guard count > 1 else { return [] }
        var samples = [Float](repeating: 0, count: count)
        let harmonic = 0.06
        for index in 0..<count {
            let fundamental = wave(index, count)
            let shaped = (fundamental + harmonic * fundamental * fundamental) / (1 + harmonic)
            let gain = envelope(index: index, count: count, fadeIn: fadeIn, fadeOut: fadeOut)
            samples[index] = Float(peak * gain * shaped)
        }
        return samples
    }

    private static func envelope(index: Int, count: Int, fadeIn: Int, fadeOut: Int) -> Double {
        let attack = fadeIn > 0 ? smoothstep(Double(index) / Double(fadeIn)) : 1
        let release = fadeOut > 0 ? smoothstep(Double(count - 1 - index) / Double(fadeOut)) : 1
        return attack * release
    }

    private static func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private static func mix(_ first: [Float], _ second: [Float], overlap: Int) -> [Float] {
        let shared = min(overlap, first.count, second.count)
        var mixed = first
        let start = first.count - shared
        if second.count > shared {
            mixed.append(contentsOf: second.dropFirst(shared))
        }
        for index in 0..<shared {
            mixed[start + index] += second[index]
        }
        return mixed
    }
}
