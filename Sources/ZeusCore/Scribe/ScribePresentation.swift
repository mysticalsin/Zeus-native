import Foundation

/// What the Scribe page and top bar show. Derived ONLY from the session machine's phase: nothing here
/// is advanced by a timer. The one time-based input is `revealElapsed`, which only decides how long the
/// post-`notesReady` wash is drawn (`.revealing` -> `.complete`); it never moves the machine.
public enum ScribePresentation: Equatable, Sendable {
    case idle
    case connecting
    case recording(elapsed: TimeInterval)
    case confirmingEnd
    /// After `recordingEnded`, until `notesReady`. Persists for as long as processing lasts.
    case writing
    /// `notesReady` just arrived: the wash surges, holds and fades while the notes swap in beneath it.
    case revealing
    case complete
    case failed(String)

    /// - Parameters:
    ///   - elapsed: the clock text value while recording (display only).
    ///   - revealElapsed: seconds since `notesReady` was applied; nil means the reveal is not being animated.
    public static func state(
        for phase: ScribePhase,
        elapsed: TimeInterval = 0,
        revealElapsed: TimeInterval? = nil,
        reduceMotion: Bool = false
    ) -> ScribePresentation {
        switch phase {
        case .idle: return .idle
        case .starting: return .connecting
        case .recording: return .recording(elapsed: elapsed)
        case .ending: return .confirmingEnd
        case .processing: return .writing
        case .complete:
            guard let revealElapsed, revealElapsed < ScribeGlow.revealDuration(reduceMotion: reduceMotion) else { return .complete }
            return .revealing
        case .failed(_, let reason): return .failed(reason)
        }
    }

    /// The glow stage this state draws. The stage is a function of the state, so it can only change on a machine event.
    public var glowStage: ScribeGlow.Stage {
        switch self {
        case .writing: return .writing
        case .revealing: return .reveal
        default: return .off
        }
    }

    /// True while the notes body must stay empty (the layout has switched, the notes are not written yet).
    public var bodyIsEmpty: Bool {
        switch self {
        case .writing: return true
        default: return false
        }
    }

    /// True while Scribe is capturing and the top bar shows its recording wings.
    public var isRecordingState: Bool {
        switch self {
        case .recording, .confirmingEnd: return true
        default: return false
        }
    }

    // MARK: Accessibility

    public var accessibilityLabel: String {
        switch self {
        case .idle: return "Scribe, ready"
        case .connecting: return "Scribe, connecting"
        case .recording: return "Scribe, recording"
        case .confirmingEnd: return "Scribe, confirm ending the meeting"
        case .writing: return "Scribe, writing notes"
        case .revealing: return "Scribe, notes ready"
        case .complete: return "Scribe, meeting notes"
        case .failed: return "Scribe, problem"
        }
    }

    public var accessibilityValue: String {
        switch self {
        case .idle: return "Not recording"
        case .connecting: return "Connecting to meeting audio"
        case .recording(let elapsed): return RecordingMotion.spokenElapsed(elapsed) ?? "Elapsed time unavailable"
        case .confirmingEnd: return "Still recording"
        case .writing: return "Writing notes. This can take a moment."
        case .revealing, .complete: return "Notes are ready"
        case .failed(let reason): return reason
        }
    }

    /// Spoken once when the state is entered; nil where entering is not worth interrupting for.
    public var announcement: String? {
        switch self {
        case .idle: return nil
        case .connecting: return "Connecting"
        case .recording: return "Recording started"
        case .confirmingEnd: return "End the meeting? This stops recording and writes your notes."
        case .writing: return "Recording ended. Writing notes."
        case .revealing: return "Notes are ready"
        case .complete: return nil
        case .failed(let reason): return "Scribe stopped. \(reason)"
        }
    }
}

/// What the recording page says about the microphone gate. Mirrors the router's rule: only an
/// `.unmuted` reading is recorded; muted and unknown (unreadable) readings are dropped.
public enum ScribeMicIndicator: Equatable, Sendable {
    case listening
    case mutedNotRecorded
    case unknownNotRecorded

    /// nil = no reading yet, which is unknown (fail closed).
    public init(_ state: ScribeMuteState?) {
        switch state {
        case .unmuted?: self = .listening
        case .muted?: self = .mutedNotRecorded
        case .unknown?, nil: self = .unknownNotRecorded
        }
    }

    public var label: String {
        switch self {
        case .listening: return "Listening"
        case .mutedNotRecorded: return "Mic muted — not recorded"
        case .unknownNotRecorded: return "Mic status unknown — not recorded"
        }
    }

    public var isRecorded: Bool { self == .listening }
}

/// System (meeting participants') audio: whether any frames have arrived this session.
public enum ScribeSystemIndicator: Equatable, Sendable {
    case waiting
    case receiving

    public init(framesReceived: Bool) { self = framesReceived ? .receiving : .waiting }

    public var label: String {
        switch self {
        case .waiting: return "Meeting audio: waiting"
        case .receiving: return "Meeting audio: receiving"
        }
    }
}

/// The live level readout on the recording page: loudness of the latest audio as 0...1, and a short history as bars.
public enum ScribeLevelMeter {
    public static let barCount = 7
    /// At or below this a bar reads as silence (drawn as a dot, not a bar).
    public static let silentBelow: Double = 0.08
    /// The quietest level shown; 0 dBFS is full scale.
    private static let floorDecibels = -50.0

    /// RMS in dBFS mapped from -50...0 onto 0...1, clamped.
    public static func level(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let rms = Double(ScribeAudioMath.rms(samples))
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels - floorDecibels) / -floorDecibels))
    }

    /// The newest `count` levels, newest last, padded with 0 in front when the history is shorter.
    public static func bars(history: [Double], count: Int = barCount) -> [Double] {
        let wanted = max(0, count)
        let recent = history.suffix(wanted).map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        return [Double](repeating: 0, count: wanted - recent.count) + recent
    }
}

/// Typewriter pacing for text that arrives in whole chunks: words appear one after another instead of at once.
public enum ScribeWordReveal {
    /// How many of `total` words show `since` seconds after the text last changed: the words already on screen
    /// plus one per 1/`wordsPerSecond` seconds since, never more than `total`. Counting from what is already
    /// shown (not from the first word) keeps new words arriving when replacement text lands every second or so.
    /// Reduce Motion shows everything at once.
    public static func visibleWords(
        total: Int,
        alreadyShown: Int,
        since: TimeInterval,
        wordsPerSecond: Double = 12,
        reduceMotion: Bool
    ) -> Int {
        let total = max(0, total)
        if reduceMotion { return total }
        let shown = min(max(0, alreadyShown), total)
        guard since.isFinite, since > 0, wordsPerSecond.isFinite, wordsPerSecond > 0 else { return shown }
        let added = Int(min(Double(total - shown), since * wordsPerSecond).rounded(.down))
        return min(total, shown + added)
    }
}

/// Speaker tints for the live transcript, readable on a dark background. Deterministic: the same speaker is
/// always the same colour, and "Speaker N" cycles through six.
public enum ScribeSpeakerPalette {
    public static let you = ScribeGlow.RGB(214, 240, 222)
    public static let unknown = ScribeGlow.RGB(150, 150, 158)
    /// Blue first, then amber, rose, teal, violet, lime.
    public static let participants: [ScribeGlow.RGB] = [
        ScribeGlow.RGB(120, 170, 255),
        ScribeGlow.RGB(240, 190, 110),
        ScribeGlow.RGB(240, 140, 170),
        ScribeGlow.RGB(100, 210, 200),
        ScribeGlow.RGB(190, 150, 250),
        ScribeGlow.RGB(170, 215, 120),
    ]

    public static func color(for speaker: ScribeSpeaker) -> ScribeGlow.RGB {
        switch speaker {
        case .you: return you
        case .unknown: return unknown
        case .participant(let label): return participants[tintIndex(for: label)]
        }
    }

    /// "Speaker N" is tint N - 1 (wrapping). The bare label system audio used before diarization is the first
    /// tint; any other name hashes (FNV-1a, so it never changes between launches).
    private static func tintIndex(for label: String) -> Int {
        let count = participants.count
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "Speaker" { return 0 }
        if trimmed.hasPrefix("Speaker "), let number = Int(trimmed.dropFirst("Speaker ".count)), number >= 1 {
            return (number - 1) % count
        }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in trimmed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(count))
    }
}

/// The measured end-of-meeting motion (CLAUDE-LEAD-20261107/SUPERWHISPER-REF/REFERENCE-MOTION.md), as pure
/// functions of a stage and the time since that stage began. Colours are Zeus's palette near the observed purples.
public enum ScribeGlow {
    public enum Stage: Equatable, Sendable {
        case off
        /// From `recordingEnded` until `notesReady`: rise, recede, then breathe for as long as it takes.
        case writing
        /// From `notesReady`: surge, hold, fade.
        case reveal
    }

    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(_ r: Double, _ g: Double, _ b: Double) {
            red = r / 255
            green = g / 255
            blue = b / 255
        }
    }

    // Colours
    public static let washColor = RGB(110, 80, 160)
    public static let edgeColor = RGB(155, 119, 185)
    public static let peakColor = RGB(115, 85, 158)

    // Writing stage
    /// The rise starts this long after the layout switch (observed 1230 -> 1400 ms).
    public static let riseDelay: TimeInterval = 0.17
    public static let riseDuration: TimeInterval = 0.45
    public static let riseHeight = 0.25
    public static let holdDuration: TimeInterval = 0.55
    public static let recedeDuration: TimeInterval = 0.8
    public static let bandBase = 0.065
    public static let bandAmplitude = 0.015
    public static let bandPeriod: TimeInterval = 1.6
    /// What Reduce Motion shows for the whole writing wait.
    public static let reducedBand = 0.06

    // Reveal stage
    public static let surgeDuration: TimeInterval = 0.4
    public static let surgeHold: TimeInterval = 0.28
    public static let fadeDuration: TimeInterval = 0.3
    /// Reduce Motion: opacity crossfade only.
    public static let crossfadeDuration: TimeInterval = 0.3

    public static func revealDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? crossfadeDuration : surgeDuration + surgeHold + fadeDuration
    }

    /// Breathing band: bandBase +- bandAmplitude (0.05...0.08), one cycle per `bandPeriod`.
    public static func band(at t: TimeInterval) -> Double {
        bandBase + bandAmplitude * sin(2 * Double.pi * t / bandPeriod)
    }

    /// Glow height as a fraction of the body, 0...1, `t` seconds after `stage` began.
    /// Reduce Motion: a static band, no rise, no surge.
    public static func glowHeight(stage: Stage, t: TimeInterval, reduceMotion: Bool) -> Double {
        let t = t.isFinite ? max(0, t) : 0
        switch stage {
        case .off:
            return 0
        case .writing:
            if reduceMotion { return reducedBand }
            let riseEnd = riseDelay + riseDuration
            let holdEnd = riseEnd + holdDuration
            if t <= riseDelay { return 0 }
            if t < riseEnd { return riseHeight * smooth((t - riseDelay) / riseDuration) }
            if t < holdEnd { return riseHeight }
            if t < holdEnd + recedeDuration {
                let k = smooth((t - holdEnd) / recedeDuration)
                return riseHeight + (band(at: t) - riseHeight) * k
            }
            return band(at: t)
        case .reveal:
            if reduceMotion { return t < crossfadeDuration ? reducedBand : 0 }
            if t < surgeDuration { return min(1, bandBase + (1 - bandBase) * smooth(t / surgeDuration)) }
            if t < revealDuration(reduceMotion: false) { return 1 }
            return 0
        }
    }

    /// Opacity of the glow layer: 1 while it is the thing on screen, fading out at the end of the reveal.
    public static func glowOpacity(stage: Stage, t: TimeInterval, reduceMotion: Bool) -> Double {
        let t = t.isFinite ? max(0, t) : 0
        switch stage {
        case .off: return 0
        case .writing: return 1
        case .reveal:
            if reduceMotion { return clamp(1 - t / crossfadeDuration) }
            let fadeStart = surgeDuration + surgeHold
            if t < fadeStart { return 1 }
            // Exactly 0 at and after the fade end (floating-point subtraction can leave ~1e-16).
            if t >= fadeStart + fadeDuration { return 0 }
            return clamp(1 - (t - fadeStart) / fadeDuration)
        }
    }

    /// Opacity of the notes while revealing: they swap in beneath the wash at the surge peak
    /// (Reduce Motion: they crossfade in). Outside the reveal the notes are fully shown.
    public static func contentOpacity(t: TimeInterval, reduceMotion: Bool) -> Double {
        let t = t.isFinite ? max(0, t) : 0
        if reduceMotion { return clamp(t / crossfadeDuration) }
        return t < surgeDuration ? 0 : 1
    }

    /// How far the band's top edge has brightened from the peak colour toward lavender (observed while it
    /// recedes). 0 until the rise ends, 1 once the band has formed.
    public static func edgeBrightness(t: TimeInterval) -> Double {
        clamp((t - riseDelay - riseDuration) / (holdDuration + recedeDuration))
    }

    private static func smooth(_ x: Double) -> Double {
        let k = clamp(x)
        return k * k * (3 - 2 * k)
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
