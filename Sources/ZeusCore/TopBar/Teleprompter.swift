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
        TeleprompterBox.blocks(in: text).map { Block(id: $0.id, isCue: $0.isCue, text: $0.text) }
    }

    public var cues: [Block] { blocks.filter(\.isCue) }

    /// Spoken words, cue titles left out.
    public var wordCount: Int { TeleprompterBox.wordCount(in: text) }

    /// Reading time at a speaking pace (words per minute), in seconds.
    public func readingTime(wordsPerMinute: Double = TeleprompterBox.defaultWordsPerMinute) -> TimeInterval {
        TeleprompterBox.readingTime(wordCount: wordCount, wordsPerMinute: wordsPerMinute)
    }
}

/// The rolling state of a teleprompter, kept free of UI so it can be tested.
/// Voice follow: the text moves only while you're speaking (with a short grace so
/// breaths don't stop it) and holds when you pause. Hovering always holds it.
public struct PrompterRoll: Equatable, Sendable {
    public typealias Phase = TeleprompterBox.Phase

    public private(set) var phase: Phase = .idle
    /// Scroll distance in points.
    public private(set) var offset: Double = 0
    /// Points per second.
    public var speed: Double
    public var voiceFollow: Bool
    /// Mic level (0...1) that counts as speaking.
    public var voiceThreshold: Double = TeleprompterBox.defaultVoiceThreshold
    /// How long the text keeps moving after you stop speaking.
    public var voiceGrace: TimeInterval = TeleprompterBox.defaultVoiceGrace
    public private(set) var countdownEndsAt: Date?
    private var lastVoiceAt: Date?

    public static let countdownLength: TimeInterval = TeleprompterBox.countdownLength
    public static let speedRange: ClosedRange<Double> = TeleprompterBox.speedRange

    public init(speed: Double = TeleprompterBox.defaultSpeed, voiceFollow: Bool = true) {
        self.speed = TeleprompterBox.clampedSpeed(speed)
        self.voiceFollow = voiceFollow
    }

    private var roll: TeleprompterBox.Roll {
        get {
            TeleprompterBox.Roll(
                phase: phase, offset: offset, speed: speed, voiceFollow: voiceFollow,
                voiceThreshold: voiceThreshold, voiceGrace: voiceGrace,
                countdownEndsAt: countdownEndsAt, lastVoiceAt: lastVoiceAt)
        }
        set {
            phase = newValue.phase
            offset = newValue.offset
            speed = newValue.speed
            voiceFollow = newValue.voiceFollow
            voiceThreshold = newValue.voiceThreshold
            voiceGrace = newValue.voiceGrace
            countdownEndsAt = newValue.countdownEndsAt
            lastVoiceAt = newValue.lastVoiceAt
        }
    }

    public mutating func start(at now: Date = Date(), countdown: Bool = true) {
        var state = roll
        TeleprompterBox.start(&state, at: now, countdown: countdown)
        roll = state
    }

    /// Whole seconds left on the countdown (3, 2, 1), or nil.
    public func countdownRemaining(at now: Date = Date()) -> Int? {
        TeleprompterBox.countdownRemaining(roll, at: now)
    }

    public mutating func pause() {
        var state = roll
        TeleprompterBox.pause(&state)
        roll = state
    }

    public mutating func resume() {
        var state = roll
        TeleprompterBox.resume(&state)
        roll = state
    }

    public mutating func stop() {
        var state = roll
        TeleprompterBox.stop(&state)
        roll = state
    }

    public mutating func adjustSpeed(by delta: Double) {
        var state = roll
        TeleprompterBox.adjustSpeed(&state, by: delta)
        roll = state
    }

    /// New text replaced the old (the next slide's notes): back to the top. A roll that was
    /// rolling or had reached the end rolls on at once, with a moment of voice grace; a paused,
    /// idle or counting-down roll keeps its phase.
    public mutating func restartSection(at now: Date = Date()) {
        var state = roll
        TeleprompterBox.restartSection(&state, at: now)
        roll = state
    }

    /// Jump to a point (a cue's position) and keep going.
    public mutating func jump(to position: Double) {
        var state = roll
        TeleprompterBox.jump(&state, to: position)
        roll = state
    }

    /// Hear the mic level; call this as levels arrive.
    public mutating func hear(level: Double, at now: Date = Date()) {
        var state = roll
        TeleprompterBox.hear(&state, level: level, at: now)
        roll = state
    }

    public func isSpeaking(at now: Date = Date()) -> Bool {
        TeleprompterBox.isSpeaking(roll, at: now)
    }

    /// Whether the text would move right now.
    public func isMoving(at now: Date = Date(), hovered: Bool) -> Bool {
        TeleprompterBox.isMoving(roll, at: now, hovered: hovered)
    }

    /// Advance by `dt` seconds. `maxOffset` is where the script ends (content minus view height).
    public mutating func tick(_ dt: TimeInterval, at now: Date = Date(), hovered: Bool, maxOffset: Double) {
        var state = roll
        TeleprompterBox.tick(&state, dt, at: now, hovered: hovered, maxOffset: maxOffset)
        roll = state
    }
}
