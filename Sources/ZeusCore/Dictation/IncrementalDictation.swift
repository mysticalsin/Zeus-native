import Foundation

/// How the chunk scheduler listens: 16 kHz audio is cut into pieces at pauses so most of a
/// dictation is already transcribed when the key comes up.
public struct ChunkSchedulerConfig: Equatable, Sendable {
    public var sampleRate: Int
    /// Loudness frames are this long.
    public var frameMilliseconds: Int
    /// A frame quieter than this (root mean square, 0 to 1) counts as silence.
    public var silenceLevel: Float
    /// A chunk is never cut shorter than this.
    public var minChunkSeconds: Double
    /// A chunk is cut here even without a pause.
    public var maxChunkSeconds: Double
    /// How long a pause must last before a chunk may end in it.
    public var pauseSeconds: Double
    /// A tail shorter than this is not worth a model call.
    public var minTailSeconds: Double

    public init(sampleRate: Int = 16_000, frameMilliseconds: Int = 20, silenceLevel: Float = 0.008,
                minChunkSeconds: Double = 3, maxChunkSeconds: Double = 12, pauseSeconds: Double = 0.4,
                minTailSeconds: Double = 0.12) {
        self.sampleRate = sampleRate
        self.frameMilliseconds = frameMilliseconds
        self.silenceLevel = silenceLevel
        self.minChunkSeconds = minChunkSeconds
        self.maxChunkSeconds = maxChunkSeconds
        self.pauseSeconds = pauseSeconds
        self.minTailSeconds = minTailSeconds
    }

    public static let standard = ChunkSchedulerConfig()

    var frameSamples: Int { max(1, sampleRate * frameMilliseconds / 1000) }
    func samples(seconds: Double) -> Int { Int((seconds * Double(sampleRate)).rounded()) }
}

/// What to do with the audio left over when the key is released.
public enum TailDecision: Equatable, Sendable {
    /// Nothing was recorded.
    case empty
    /// Every spoken part already went to the model; the tail is silence or too short.
    case skipTail
    /// Transcribe only this part of the recording. A range starting at 0 is the whole recording
    /// (a short dictation that never reached a chunk boundary).
    case transcribeTail(Range<Int>)
}

/// Decides when to send finished stretches of a live recording to the speech model. Pure: it
/// only counts samples and measures loudness, so it runs the same in tests and in the app.
public struct ChunkScheduler: Equatable, Sendable {
    public let config: ChunkSchedulerConfig
    /// Every sample passed to `append`.
    public private(set) var totalSamples = 0
    /// Samples before this index were already handed out (or were silence).
    public private(set) var committedSamples = 0
    private var analyzedSamples = 0
    private var trailingSilentSamples = 0
    private var voicedSinceCommit = 0
    /// Chunks handed out so far.
    public private(set) var chunksEmitted = 0
    private var frameSum: Float = 0
    private var frameCount = 0

    public init(config: ChunkSchedulerConfig = .standard) {
        self.config = config
    }

    /// Takes the next audio and returns the range of finished chunks to transcribe now (empty
    /// most of the time). A chunk ends at a pause once it is long enough, or at the maximum length.
    public mutating func append(_ samples: [Float]) -> [Range<Int>] {
        totalSamples += samples.count
        let frame = config.frameSamples
        for sample in samples {
            frameSum += sample * sample
            frameCount += 1
            if frameCount == frame {
                let level = (frameSum / Float(frame)).squareRoot()
                analyzedSamples += frame
                if level < config.silenceLevel {
                    trailingSilentSamples += frame
                } else {
                    trailingSilentSamples = 0
                    voicedSinceCommit += frame
                }
                frameSum = 0
                frameCount = 0
            }
        }
        let pending = analyzedSamples - committedSamples
        let reachedPause = pending >= config.samples(seconds: config.minChunkSeconds)
            && trailingSilentSamples >= config.samples(seconds: config.pauseSeconds)
        let reachedMax = pending >= config.samples(seconds: config.maxChunkSeconds)
        guard reachedPause || reachedMax else { return [] }
        let range = committedSamples..<analyzedSamples
        let spoken = voicedSinceCommit > 0
        committedSamples = analyzedSamples
        voicedSinceCommit = 0
        // A stretch of pure silence advances the cursor but costs no model call.
        if spoken { chunksEmitted += 1 }
        return spoken ? [range] : []
    }

    /// What the release has left to do. With no chunk sent yet the tail is the whole recording: a dictation
    /// is never dropped because its level looked like silence.
    public func finalDecision() -> TailDecision {
        guard totalSamples > 0 else { return .empty }
        if chunksEmitted == 0 { return .transcribeTail(0..<totalSamples) }
        let remaining = totalSamples - committedSamples
        guard remaining >= config.samples(seconds: config.minTailSeconds), remaining > 0 else { return .skipTail }
        // No loud frame since the last chunk: only silence is left (an unmeasured part frame is under 20 ms).
        if voicedSinceCommit == 0 { return .skipTail }
        return .transcribeTail(committedSamples..<totalSamples)
    }
}

/// Puts chunk transcripts back together in recording order.
public enum ChunkTranscriptJoiner {
    public static func join(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Keeps a speech model in memory for a while after its last use so the next key press starts fast,
/// then lets it go. Pure: the caller passes the clock and applies the answer.
public struct ModelKeepAlivePolicy: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case unload
        /// Look again after this many seconds.
        case checkAgain(after: TimeInterval)
    }

    /// Ten minutes, the same as the apps people compare Zeus with.
    public static let defaultSeconds: TimeInterval = 600

    public var keepAliveSeconds: TimeInterval

    public init(keepAliveSeconds: TimeInterval = ModelKeepAlivePolicy.defaultSeconds) {
        self.keepAliveSeconds = max(0, keepAliveSeconds)
    }

    /// `lastUse` is when the model last started or finished work; `activeUses` counts work running now.
    public func evaluate(lastUse: Date?, activeUses: Int, now: Date) -> Action {
        if activeUses > 0 { return .checkAgain(after: keepAliveSeconds) }
        guard let lastUse else { return .unload }
        let idle = now.timeIntervalSince(lastUse)
        if idle >= keepAliveSeconds { return .unload }
        return .checkAgain(after: keepAliveSeconds - max(0, idle))
    }
}

/// One dictation's speed numbers, for the [ZEUS] log line.
public struct DictationLatency: Equatable, Sendable {
    /// Release until the text was pasted or typed.
    public var releaseToTextMs: Int
    /// Release until the speech model returned the final text.
    public var transcribeMs: Int
    public var audioMs: Int
    public var engine: String
    public var insertion: String

    public static let targetMs = 300

    public init(releaseToTextMs: Int, transcribeMs: Int, audioMs: Int, engine: String, insertion: String) {
        self.releaseToTextMs = releaseToTextMs
        self.transcribeMs = transcribeMs
        self.audioMs = audioMs
        self.engine = engine
        self.insertion = insertion
    }

    public static func milliseconds(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1000).rounded()))
    }

    public var withinTarget: Bool { releaseToTextMs < Self.targetMs }

    /// Metadata only. Dictated words never go to the log.
    public var logLine: String {
        "dictation: release->text \(releaseToTextMs) ms (transcribe \(transcribeMs) ms, audio \(audioMs) ms, "
            + "engine \(engine), insert \(insertion), \(withinTarget ? "within" : "over") \(Self.targetMs) ms target)"
    }
}
