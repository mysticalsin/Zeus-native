import Foundation

/// Cuts a stream of 16 kHz mono audio into utterances by energy: a short run of loud frames starts
/// one, about 0.7 s of quiet ends it. While someone keeps talking it also hands out a growing
/// partial every few seconds, and it cuts a very long monologue so captions never lag.
public struct PolyglotSegmenter: Sendable {
    public struct Config: Sendable {
        public var sampleRate = 16_000
        /// 20 ms frames.
        public var frame = 320
        public var threshold: Float = 0.012
        public var startFrames = 3
        public var hangoverFrames = 35
        public var prerollFrames = 10
        public var minSpeechFrames = 15
        public var maxFrames = 750
        public var partialEveryFrames = 150
        public init() {}
    }

    /// Every event names its utterance: a partial and the final that settles it share the number,
    /// which counts up for the life of this segmenter (a long monologue cut mid-speech starts a new one).
    public enum Event: Equatable, Sendable {
        case partial(utterance: Int, samples: [Float])
        case final(utterance: Int, samples: [Float])
    }

    private let config: Config
    private var utterance = 0
    private var pending: [Float] = []
    private var speaking = false
    private var preroll: [[Float]] = []
    private var current: [Float] = []
    private var loudRun = 0
    private var silentRun = 0
    private var speechFrames = 0
    private var floor: Float = 0

    public init(config: Config = Config()) { self.config = config }

    public var isSpeaking: Bool { speaking }

    public mutating func feed(_ samples: [Float]) -> [Event] {
        pending.append(contentsOf: samples)
        var events: [Event] = []
        while pending.count >= config.frame {
            let frame = Array(pending.prefix(config.frame))
            pending.removeFirst(config.frame)
            step(frame, into: &events)
        }
        return events
    }

    /// The listener stopped: whatever was being said still counts.
    public mutating func flush() -> [Event] {
        var events: [Event] = []
        if speaking, speechFrames >= config.minSpeechFrames {
            events.append(.final(utterance: utterance, samples: trimmed()))
        }
        reset()
        pending.removeAll()
        return events
    }

    private func rms(_ frame: [Float]) -> Float {
        guard !frame.isEmpty else { return 0 }
        return (frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count)).squareRoot()
    }

    private mutating func step(_ frame: [Float], into events: inout [Event]) {
        let level = rms(frame)
        let loud = level > max(config.threshold, floor * 2.5)
        if !speaking {
            if !loud { floor = floor * 0.95 + level * 0.05 }
            preroll.append(frame)
            if preroll.count > config.prerollFrames { preroll.removeFirst() }
            loudRun = loud ? loudRun + 1 : 0
            if loudRun >= config.startFrames {
                speaking = true
                utterance += 1
                current = preroll.flatMap { $0 }
                speechFrames = loudRun
                silentRun = 0
                preroll.removeAll()
            }
            return
        }
        current.append(contentsOf: frame)
        if loud {
            silentRun = 0
            speechFrames += 1
        } else {
            silentRun += 1
        }
        let frames = current.count / config.frame
        if silentRun >= config.hangoverFrames {
            if speechFrames >= config.minSpeechFrames { events.append(.final(utterance: utterance, samples: trimmed())) }
            reset()
        } else if frames >= config.maxFrames {
            events.append(.final(utterance: utterance, samples: current))
            utterance += 1
            current = []
            speechFrames = loud ? 1 : 0
            silentRun = 0
        } else if loud, frames > 0, frames % config.partialEveryFrames == 0 {
            events.append(.partial(utterance: utterance, samples: current))
        }
    }

    /// Drops the trailing silence but keeps a little tail so words do not end abruptly.
    private func trimmed() -> [Float] {
        let drop = max(silentRun - 5, 0) * config.frame
        return drop > 0 && drop < current.count ? Array(current.dropLast(drop)) : current
    }

    private mutating func reset() {
        speaking = false
        current = []
        loudRun = 0
        silentRun = 0
        speechFrames = 0
        preroll.removeAll()
    }
}
