import Foundation

/// The sound that marks the start and the end of a dictation (Settings > Dictation).
public enum DictationCueStyle: String, CaseIterable, Sendable {
    /// Two soft glass notes, rising on start and falling on stop (scripts/gen-dictation-sounds.py).
    case crystal = "Crystal"
    /// The bundled click Zeus has always used.
    case softClick = "Soft click"
    case glass = "Glass"
    case pop = "Pop"
    /// A short warm blip: rising on start, falling on stop.
    case airy = "Airy"
    case none = "None"

    public static let defaultStyle: DictationCueStyle = .crystal

    /// An unknown or missing saved value means the default.
    public init(saved: String?) {
        self = DictationCueStyle(rawValue: saved ?? "") ?? Self.defaultStyle
    }

    public var title: String { rawValue }

    /// Whether `DictationCueSynth` makes this sound (Crystal and Soft click are bundled files, None is silence).
    public var isSynthesized: Bool { self == .glass || self == .pop || self == .airy }
}

/// Start and stop of a dictation; cancel also marks a turn that ended with an error (no speech, no mic).
public enum DictationCuePhase: Sendable, CaseIterable { case start, stop, cancel }

/// Where one cue's audio comes from.
public enum DictationCueSource: Equatable, Sendable {
    case silent
    /// Made in code by `DictationCueSynth`.
    case synthesized(DictationCueStyle, DictationCuePhase)
    /// A file in the app's Sounds folder, listed in `SoundCatalog`.
    case bundled(SoundSlot, style: String)

    /// Every style shares one gentle low blip for cancel and errors; None is silent throughout.
    public static func resolve(_ style: DictationCueStyle, _ phase: DictationCuePhase) -> DictationCueSource {
        if style == .none { return .silent }
        if phase == .cancel { return .bundled(.dictationCancel, style: "Dictation cancel") }
        let slot: SoundSlot = phase == .start ? .dictationBegin : .dictationEnd
        switch style {
        case .crystal: return .bundled(slot, style: style.rawValue)
        case .softClick: return .bundled(slot, style: phase == .start ? "Dictation begin" : "Dictation end")
        case .glass, .pop, .airy: return .synthesized(style, phase)
        case .none: return .silent
        }
    }
}

/// Which dictation moments make a sound. Every trigger (hold, double-tap, press to toggle, Fn or
/// Command keys, the top bar button, links) ends in the controller's begin, finish and cancel,
/// which run through `DictationFlow`; this rule maps those flow events to cues.
public enum DictationCueRule {
    /// The cue an event asks for, given the flow state before it. The start cue is not here: it
    /// sounds before the microphone opens (`beginCapture`), not when the flow hears about it.
    public static func cue(for event: DictationFlow.Event, before state: DictationFlow.State) -> DictationCuePhase? {
        switch event {
        case .finishRequested:
            // Key released or pressed again: the stop cue sounds now, not after transcription.
            return state.isListening ? .stop : nil
        case .cancelRequested:
            return isLiveTurn(state) ? .cancel : nil
        case .startFailed:
            return state.canStartJob ? .cancel : nil
        case .failed(let turn, _):
            // A live turn that heard nothing; files and history re-runs stay quiet.
            return isLiveTurn(state) && state.turn == turn ? .cancel : nil
        case .micOpened, .fileRequested, .rewriteStarted, .succeeded, .dismissed:
            return nil
        }
    }

    /// Key down: the start cue first, then the microphone. The cue is never late behind a slow
    /// device start, and it is already playing before the first sample is captured.
    public static func beginCapture<T>(cue: (DictationCuePhase) -> Void, open: () throws -> T) rethrows -> T {
        cue(.start)
        return try open()
    }

    private static func isLiveTurn(_ state: DictationFlow.State) -> Bool {
        switch state {
        case .listening: true
        case .transcribing(_, let source), .rewriting(_, let source): source == .live
        case .idle, .done, .failed: false
        }
    }
}

/// Zeus's own start and stop sounds, made from sine waves in code. Nothing is sampled or copied
/// from another app; every value below is a plain tone, a pitch glide and a volume envelope.
public enum DictationCueSynth {
    public static let sampleRate = 44_100
    public static let defaultVolume = 70

    public static func clampedVolume(_ percent: Int) -> Int { min(100, max(0, percent)) }

    /// Mono samples in -1...1; empty for the bundled styles, None and the shared cancel blip.
    public static func samples(_ style: DictationCueStyle, _ phase: DictationCuePhase) -> [Float] {
        guard phase != .cancel else { return [] }
        return switch style {
        case .airy: airy(phase)
        case .glass: glass(phase)
        case .pop: pop(phase)
        case .crystal, .softClick, .none: []
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
