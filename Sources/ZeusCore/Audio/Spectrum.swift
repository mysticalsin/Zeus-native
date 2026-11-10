import Accelerate
import Foundation

/// The maths behind the live audio visualizer: samples in, log-spaced band levels out.
/// Pure and testable; the CoreAudio capture that feeds it lives in the app target.
public enum SpectrumMath {
    public static let bandCount = 28
    public static let fftSize = 2048
    public static let minFrequency: Double = 40
    public static let maxFrequency: Double = 16_000

    /// Band edges in Hz, `bands + 1` values spaced evenly on a log axis.
    public static func bandEdges(bands: Int = bandCount, sampleRate: Double) -> [Double] {
        let top = min(maxFrequency, sampleRate / 2 * 0.98)
        let ratio = pow(top / minFrequency, 1 / Double(bands))
        return (0...bands).map { minFrequency * pow(ratio, Double($0)) }
    }

    /// The band a frequency falls in, or nil outside the range.
    public static func band(forFrequency hz: Double, bands: Int = bandCount, sampleRate: Double) -> Int? {
        let edges = bandEdges(bands: bands, sampleRate: sampleRate)
        guard hz >= edges[0], hz < edges[bands] else { return nil }
        return edges.lastIndex { $0 <= hz }.map { min($0, bands - 1) }
    }

    /// Smoothing step: rises quickly, falls slowly, independent of the frame rate.
    public static func smooth(previous: [Float], target: [Float], dt: Double, attack: Double = 0.045, decay: Double = 0.22) -> [Float] {
        guard previous.count == target.count else { return target }
        let up = Float(1 - exp(-dt / attack)), down = Float(1 - exp(-dt / decay))
        return zip(previous, target).map { old, new in old + (new - old) * (new > old ? up : down) }
    }

    /// Slider value (percent, 100 = normal) to a gain on the 0...1 band levels.
    public static func gain(sensitivityPercent: Double) -> Float { Float(min(max(sensitivityPercent, 25), 300) / 100) }
}

/// Windowed FFT into log-spaced bands. One instance per capture; not thread safe.
public final class SpectrumAnalyzer {
    public let sampleRate: Double
    public let bands: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var windowed: [Float]
    private var ranges: [Range<Int>] = []
    private let size = SpectrumMath.fftSize

    public init(sampleRate: Double, bands: Int = SpectrumMath.bandCount) {
        self.sampleRate = sampleRate
        self.bands = bands
        log2n = vDSP_Length(log2(Double(SpectrumMath.fftSize)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: SpectrumMath.fftSize)
        vDSP_hann_window(&window, vDSP_Length(SpectrumMath.fftSize), 0)
        real = [Float](repeating: 0, count: SpectrumMath.fftSize / 2)
        imag = real
        windowed = [Float](repeating: 0, count: SpectrumMath.fftSize)
        let edges = SpectrumMath.bandEdges(bands: bands, sampleRate: sampleRate)
        let binHz = sampleRate / Double(SpectrumMath.fftSize)
        var lastEnd = 1
        for i in 0..<bands {
            let lo = max(lastEnd, Int((edges[i] / binHz).rounded(.down)))
            let hi = max(lo + 1, Int((edges[i + 1] / binHz).rounded(.down)))
            ranges.append(lo..<min(hi, SpectrumMath.fftSize / 2))
            lastEnd = min(hi, SpectrumMath.fftSize / 2 - 1)
        }
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Band levels 0...1 for the last `fftSize` mono samples (shorter input is zero padded).
    /// Levels map -75 dB...-15 dB (relative to full scale) onto 0...1.
    public func levels(samples: [Float]) -> [Float] {
        let n = size
        if samples.count >= n {
            samples.withUnsafeBufferPointer { src in
                vDSP_vmul(src.baseAddress! + (samples.count - n), 1, window, 1, &windowed, 1, vDSP_Length(n))
            }
        } else {
            for i in 0..<n { windowed[i] = i < samples.count ? samples[i] * window[i] : 0 }
        }
        var out = [Float](repeating: 0, count: bands)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { w in
                    w.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2)) }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                // Squared magnitude per bin, scaled so a full-scale sine reads about 0 dB.
                var mags = [Float](repeating: 0, count: n / 2)
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
                let scale = 4 / Float(n * n) // zrip returns 2x the DFT; a Hann window passes half a sine's amplitude
                for (i, range) in ranges.enumerated() {
                    var peak: Float = 0
                    for bin in range { peak = max(peak, mags[bin]) }
                    let db = 10 * log10(max(peak * scale, 1e-12))
                    out[i] = min(1, max(0, (db + 75) / 60))
                }
            }
        }
        return out
    }
}

/// A short rolling window of mono samples. The audio thread writes, the analysis timer reads.
public final class SampleRing: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [Float]
    private var head = 0
    private var filled = 0

    public init(capacity: Int = SpectrumMath.fftSize * 2) { buffer = [Float](repeating: 0, count: capacity) }

    public func write(_ pointer: UnsafePointer<Float>, count: Int) {
        lock.lock(); defer { lock.unlock() }
        for i in 0..<count {
            buffer[head] = pointer[i]
            head = (head + 1) % buffer.count
        }
        filled = min(buffer.count, filled + count)
    }

    /// The newest `count` samples, oldest first (zero padded at the front when fewer have arrived).
    public func latest(_ count: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        var out = [Float](repeating: 0, count: count)
        let take = min(count, filled)
        for i in 0..<take {
            out[count - take + i] = buffer[(head - take + i + buffer.count * 2) % buffer.count]
        }
        return out
    }
}

/// Where the System Audio Recording permission stands, as far as Zeus knows. macOS has no
/// public way to ask without trying, so this records the outcome of the attempts the person started.
public enum AudioCapturePermission: String, Sendable {
    case notAsked, allowed, refused

    public var label: String {
        switch self {
        case .notAsked: "Not asked yet"
        case .allowed: "Allowed"
        case .refused: "Refused"
        }
    }
}

public enum SpectrumGate {
    /// Whether the capture and analysis should run at all. Anything else costs nothing.
    public static func shouldRun(wavesVisible: Bool, closedSpectrumOn: Bool, musicPlaying: Bool) -> Bool {
        wavesVisible || (closedSpectrumOn && musicPlaying)
    }

    /// Analysis rate: the big card gets 60 fps, the closed notch light 30.
    public static func framesPerSecond(wavesVisible: Bool) -> Double { wavesVisible ? 60 : 30 }

    public enum Decision: Equatable, Sendable { case capture, wait, needsSettings }

    /// What to do about the permission. Only something the person just did (turning the feature on,
    /// opening the Waves tab, pressing Allow) may start the one macOS prompt.
    public static func decision(permission: AudioCapturePermission, personAsked: Bool) -> Decision {
        switch permission {
        case .allowed: .capture
        case .notAsked: personAsked ? .capture : .wait
        case .refused: .needsSettings
        }
    }
}

public enum WaveStyle: String, CaseIterable, Identifiable, Sendable {
    case bars = "Bars", wave = "Wave", mirror = "Mirror"
    public var id: String { rawValue }
    public static func parse(_ raw: String) -> WaveStyle { WaveStyle(rawValue: raw) ?? .bars }
}
