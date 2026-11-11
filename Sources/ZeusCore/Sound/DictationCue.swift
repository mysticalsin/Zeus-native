import Foundation

/// The sound that marks the start and the end of a dictation (Settings > Dictation).
public enum DictationCueStyle: String, CaseIterable, Sendable {
    /// The bundled click Zeus has always used.
    case softClick = "Soft click"
    case glass = "Glass"
    case pop = "Pop"
    /// A short warm blip: rising on start, falling on stop.
    case airy = "Airy"
    case none = "None"

    public static let defaultStyle: DictationCueStyle = .airy

    /// An unknown or missing saved value means the default.
    public init(saved: String?) {
        self = DictationCueStyle(rawValue: saved ?? "") ?? Self.defaultStyle
    }

    public var title: String { rawValue }

    /// Whether `DictationCueSynth` makes this sound (Soft click is a bundled file, None is silence).
    public var isSynthesized: Bool { self == .glass || self == .pop || self == .airy }
}

public enum DictationCuePhase: Sendable { case start, stop }

/// Zeus's own start and stop sounds, made from sine waves in code. Nothing is sampled or copied
/// from another app; every value below is a plain tone, a pitch glide and a volume envelope.
public enum DictationCueSynth {
    public static let sampleRate = 44_100
    public static let defaultVolume = 70

    public static func clampedVolume(_ percent: Int) -> Int { min(100, max(0, percent)) }

    /// Mono samples in -1...1; empty for Soft click and None.
    public static func samples(_ style: DictationCueStyle, _ phase: DictationCuePhase) -> [Float] {
        switch style {
        case .airy: airy(phase)
        case .glass: glass(phase)
        case .pop: pop(phase)
        case .softClick, .none: []
        }
    }

    /// A 16-bit mono WAV file of the sound, or nil when the style is not synthesized.
    public static func wav(_ style: DictationCueStyle, _ phase: DictationCuePhase) -> Data? {
        let signal = samples(style, phase)
        guard !signal.isEmpty else { return nil }
        var pcm = Data(capacity: signal.count * 2)
        for sample in signal {
            let value = Int16((max(-1, min(1, sample)) * Float(Int16.max)).rounded())
            withUnsafeBytes(of: value.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        put(UInt32(36 + pcm.count))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(sampleRate)); put(UInt32(sampleRate * 2)); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        put(UInt32(pcm.count))
        data.append(pcm)
        return data
    }

    // MARK: Voices

    /// Warm blip: a sine gliding between two notes with a quiet octave above and below.
    private static func airy(_ phase: DictationCuePhase) -> [Float] {
        let rising = phase == .start
        let from: Double = rising ? 520 : 780
        let to: Double = rising ? 800 : 470
        let length = rising ? 0.16 : 0.19
        var angle = 0.0
        return render(seconds: length, peak: 0.55) { t in
            let progress = min(1, t / 0.12)
            let eased = progress * progress * (3 - 2 * progress)
            angle += 2 * Double.pi * (from + (to - from) * eased) / Double(sampleRate)
            let tone = sin(angle) + 0.28 * sin(2 * angle) + 0.12 * sin(angle / 2)
            return tone * envelope(t, attack: 0.014, decay: 0.07)
        }
    }

    /// Glass: a bright struck tone with inharmonic overtones that ring out.
    private static func glass(_ phase: DictationCuePhase) -> [Float] {
        let base: Double = phase == .start ? 1175 : 880
        let partials: [(ratio: Double, level: Double)] = [(1, 1), (2.32, 0.5), (4.25, 0.25), (6.63, 0.12)]
        return render(seconds: 0.42, peak: 0.45) { t in
            var sum = 0.0
            for (index, partial) in partials.enumerated() {
                let decay = 0.14 / Double(index + 1)
                sum += partial.level * sin(2 * Double.pi * base * partial.ratio * t) * envelope(t, attack: 0.002, decay: decay)
            }
            return sum
        }
    }

    /// Pop: a short sine whose pitch falls fast, like a soft bubble.
    private static func pop(_ phase: DictationCuePhase) -> [Float] {
        let top: Double = phase == .start ? 620 : 440
        let floor: Double = phase == .start ? 190 : 130
        var angle = 0.0
        return render(seconds: 0.10, peak: 0.7) { t in
            angle += 2 * Double.pi * (floor + (top - floor) * exp(-t / 0.018)) / Double(sampleRate)
            return sin(angle) * envelope(t, attack: 0.002, decay: 0.03)
        }
    }

    // MARK: Helpers

    /// Quick linear attack, then an exponential fall.
    private static func envelope(_ t: Double, attack: Double, decay: Double) -> Double {
        min(1, t / attack) * exp(-t / decay)
    }

    /// Renders `seconds` of audio, scales the loudest point to `peak`, and fades the last 6 ms to zero.
    private static func render(seconds: Double, peak: Float, _ voice: (Double) -> Double) -> [Float] {
        let count = Int(seconds * Double(sampleRate))
        var signal = (0..<count).map { Float(voice(Double($0) / Double(sampleRate))) }
        let loudest = signal.map { abs($0) }.max() ?? 0
        guard loudest > 0 else { return signal }
        let scale = peak / loudest
        let fade = Int(0.006 * Double(sampleRate))
        for index in signal.indices {
            var value = signal[index] * scale
            let fromEnd = count - 1 - index
            if fromEnd < fade { value *= Float(fromEnd) / Float(fade) }
            signal[index] = value
        }
        return signal
    }
}
