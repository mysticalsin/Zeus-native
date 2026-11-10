import Foundation

/// A teleprompter script. Lines that start with `#` are cues: section titles you can jump to.
public struct PrompterScript: Equatable, Sendable {
    public struct Block: Equatable, Sendable, Identifiable {
        public var id: Int
        public var isCue: Bool
        public var text: String
    }

    public var text: String

    public init(_ text: String) { self.text = text }

    /// The script as display blocks: cue titles and the paragraphs between them. Blank lines split paragraphs.
    public var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        func flush() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { result.append(Block(id: result.count, isCue: false, text: joined)) }
            paragraph = []
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                flush()
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { result.append(Block(id: result.count, isCue: true, text: title)) }
            } else if line.isEmpty {
                flush()
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return result
    }

    public var cues: [Block] { blocks.filter(\.isCue) }

    /// Spoken words, cue titles left out.
    public var wordCount: Int {
        blocks.filter { !$0.isCue }.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    /// Reading time at a speaking pace (words per minute), in seconds.
    public func readingTime(wordsPerMinute: Double = 150) -> TimeInterval {
        guard wordsPerMinute > 0 else { return 0 }
        return Double(wordCount) / wordsPerMinute * 60
    }
}

/// The rolling state of a teleprompter, kept free of UI so it can be tested.
/// Voice follow: the text moves only while you're speaking (with a short grace so
/// breaths don't stop it) and holds when you pause. Hovering always holds it.
public struct PrompterRoll: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case idle, countdown, rolling, paused, finished }

    public private(set) var phase: Phase = .idle
    /// Scroll distance in points.
    public private(set) var offset: Double = 0
    /// Points per second.
    public var speed: Double
    public var voiceFollow: Bool
    /// Mic level (0...1) that counts as speaking.
    public var voiceThreshold: Double = 0.12
    /// How long the text keeps moving after you stop speaking.
    public var voiceGrace: TimeInterval = 0.7
    public private(set) var countdownEndsAt: Date?
    private var lastVoiceAt: Date?

    public static let countdownLength: TimeInterval = 3
    public static let speedRange: ClosedRange<Double> = 8...120

    public init(speed: Double = 32, voiceFollow: Bool = true) {
        self.speed = min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
        self.voiceFollow = voiceFollow
    }

    public mutating func start(at now: Date = Date(), countdown: Bool = true) {
        offset = 0
        lastVoiceAt = nil
        if countdown {
            phase = .countdown
            countdownEndsAt = now.addingTimeInterval(Self.countdownLength)
        } else {
            phase = .rolling
            countdownEndsAt = nil
        }
    }

    /// Whole seconds left on the countdown (3, 2, 1), or nil.
    public func countdownRemaining(at now: Date = Date()) -> Int? {
        guard phase == .countdown, let end = countdownEndsAt else { return nil }
        return max(1, Int((end.timeIntervalSince(now)).rounded(.up)))
    }

    public mutating func pause() { if phase == .rolling || phase == .countdown { phase = .paused; countdownEndsAt = nil } }
    public mutating func resume() { if phase == .paused || phase == .finished { phase = .rolling } }
    public mutating func stop() { phase = .idle; offset = 0; countdownEndsAt = nil }

    public mutating func adjustSpeed(by delta: Double) {
        speed = min(max(speed + delta, Self.speedRange.lowerBound), Self.speedRange.upperBound)
    }

    /// New text replaced the old (the next slide's notes): back to the top. A roll that was
    /// rolling or had reached the end rolls on at once, with a moment of voice grace; a paused,
    /// idle or counting-down roll keeps its phase.
    public mutating func restartSection(at now: Date = Date()) {
        offset = 0
        switch phase {
        case .rolling, .finished:
            phase = .rolling
            lastVoiceAt = now
        case .idle, .paused, .countdown:
            break
        }
    }

    /// Jump to a point (a cue's position) and keep going.
    public mutating func jump(to position: Double) {
        offset = max(0, position)
        if phase == .finished { phase = .rolling }
    }

    /// Hear the mic level; call this as levels arrive.
    public mutating func hear(level: Double, at now: Date = Date()) {
        if level >= voiceThreshold { lastVoiceAt = now }
    }

    public func isSpeaking(at now: Date = Date()) -> Bool {
        guard let lastVoiceAt else { return false }
        return now.timeIntervalSince(lastVoiceAt) <= voiceGrace
    }

    /// Whether the text would move right now.
    public func isMoving(at now: Date = Date(), hovered: Bool) -> Bool {
        phase == .rolling && !hovered && (!voiceFollow || isSpeaking(at: now))
    }

    /// Advance by `dt` seconds. `maxOffset` is where the script ends (content minus view height).
    public mutating func tick(_ dt: TimeInterval, at now: Date = Date(), hovered: Bool, maxOffset: Double) {
        if phase == .countdown, let end = countdownEndsAt, now >= end {
            phase = .rolling
            countdownEndsAt = nil
            lastVoiceAt = now  // a moment of grace so the first words aren't missed
        }
        guard isMoving(at: now, hovered: hovered), dt > 0 else { return }
        offset = min(offset + speed * dt, max(0, maxOffset))
        if maxOffset > 0, offset >= maxOffset { phase = .finished }
    }
}
