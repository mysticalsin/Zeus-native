import Foundation

/// Script blocks, reading time, and the teleprompter roll.
/// The caller supplies the script text, the roll, and the current time.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum TeleprompterBox {
    public struct Block: Equatable, Sendable, Identifiable {
        public var id: Int
        public var isCue: Bool
        public var text: String

        public init(id: Int, isCue: Bool, text: String) {
            self.id = id
            self.isCue = isCue
            self.text = text
        }
    }

    public static let countdownLength: TimeInterval = 3
    public static let speedRange: ClosedRange<Double> = 8...120
    public static let defaultSpeed: Double = 32
    public static let defaultVoiceThreshold: Double = 0.12
    public static let defaultVoiceGrace: TimeInterval = 0.7
    public static let defaultWordsPerMinute: Double = 150

    public enum Phase: Equatable, Sendable {
        case idle, countdown, rolling, paused, finished
    }

    public struct Roll: Equatable, Sendable {
        public var phase: Phase
        public var offset: Double
        public var speed: Double
        public var voiceFollow: Bool
        public var voiceThreshold: Double
        public var voiceGrace: TimeInterval
        public var countdownEndsAt: Date?
        public var lastVoiceAt: Date?

        public init(phase: Phase = .idle,
                    offset: Double = 0,
                    speed: Double = TeleprompterBox.defaultSpeed,
                    voiceFollow: Bool = true,
                    voiceThreshold: Double = TeleprompterBox.defaultVoiceThreshold,
                    voiceGrace: TimeInterval = TeleprompterBox.defaultVoiceGrace,
                    countdownEndsAt: Date? = nil,
                    lastVoiceAt: Date? = nil) {
            self.phase = phase
            self.offset = offset
            self.speed = speed
            self.voiceFollow = voiceFollow
            self.voiceThreshold = voiceThreshold
            self.voiceGrace = voiceGrace
            self.countdownEndsAt = countdownEndsAt
            self.lastVoiceAt = lastVoiceAt
        }
    }

    /// Cue titles and the paragraphs between them. Blank lines split paragraphs.
    /// A line whose first character is `#` is a cue. Hashes and surrounding spaces are not part of the title.
    /// A cue with no title is dropped.
    public static func blocks(in text: String) -> [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        func flush() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty {
                result.append(Block(id: result.count, isCue: false, text: joined))
            }
            paragraph = []
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                flush()
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    result.append(Block(id: result.count, isCue: true, text: title))
                }
            } else if line.isEmpty {
                flush()
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return result
    }

    /// Spoken words, cue titles left out. Interior spaces stay one word break.
    public static func wordCount(in text: String) -> Int {
        blocks(in: text).filter { !$0.isCue }.reduce(0) { count, block in
            count + block.text.split(whereSeparator: \.isWhitespace).count
        }
    }

    /// Seconds at a speaking pace. A pace that is not positive is no time.
    public static func readingTime(wordCount: Int, wordsPerMinute: Double) -> TimeInterval {
        guard wordsPerMinute > 0 else { return 0 }
        return Double(wordCount) / wordsPerMinute * 60
    }

    /// Finite speeds land on 8...120. A non-finite speed stays non-finite when it is not infinite.
    public static func clampedSpeed(_ speed: Double) -> Double {
        min(max(speed, speedRange.lowerBound), speedRange.upperBound)
    }

    public static func start(_ roll: inout Roll, at now: Date, countdown: Bool) {
        roll.offset = 0
        roll.lastVoiceAt = nil
        if countdown {
            roll.phase = .countdown
            roll.countdownEndsAt = now.addingTimeInterval(countdownLength)
        } else {
            roll.phase = .rolling
            roll.countdownEndsAt = nil
        }
    }

    /// Whole seconds left (3, 2, 1). A countdown that has already reached its end still reads 1 until the roll ticks.
    public static func countdownRemaining(_ roll: Roll, at now: Date) -> Int? {
        guard roll.phase == .countdown, let end = roll.countdownEndsAt else { return nil }
        return max(1, Int((end.timeIntervalSince(now)).rounded(.up)))
    }

    public static func pause(_ roll: inout Roll) {
        if roll.phase == .rolling || roll.phase == .countdown {
            roll.phase = .paused
            roll.countdownEndsAt = nil
        }
    }

    public static func resume(_ roll: inout Roll) {
        if roll.phase == .paused || roll.phase == .finished {
            roll.phase = .rolling
        }
    }

    public static func stop(_ roll: inout Roll) {
        roll.phase = .idle
        roll.offset = 0
        roll.countdownEndsAt = nil
    }

    public static func adjustSpeed(_ roll: inout Roll, by delta: Double) {
        roll.speed = min(max(roll.speed + delta, speedRange.lowerBound), speedRange.upperBound)
    }

    /// Back to the top. A rolling or finished roll continues, with voice grace from `now`.
    /// A paused, idle, or counting-down roll keeps its phase.
    public static func restartSection(_ roll: inout Roll, at now: Date) {
        roll.offset = 0
        switch roll.phase {
        case .rolling, .finished:
            roll.phase = .rolling
            roll.lastVoiceAt = now
        case .idle, .paused, .countdown:
            break
        }
    }

    /// A negative or non-finite point sits at the start. A finished roll continues.
    public static func jump(_ roll: inout Roll, to position: Double) {
        roll.offset = max(0, position)
        if roll.phase == .finished { roll.phase = .rolling }
    }

    public static func hear(_ roll: inout Roll, level: Double, at now: Date) {
        if level >= roll.voiceThreshold { roll.lastVoiceAt = now }
    }

    public static func isSpeaking(_ roll: Roll, at now: Date) -> Bool {
        guard let lastVoiceAt = roll.lastVoiceAt else { return false }
        return now.timeIntervalSince(lastVoiceAt) <= roll.voiceGrace
    }

    public static func isMoving(_ roll: Roll, at now: Date, hovered: Bool) -> Bool {
        roll.phase == .rolling && !hovered && (!roll.voiceFollow || isSpeaking(roll, at: now))
    }

    /// Advance by `dt` seconds. A countdown that has ended starts rolling, with voice grace, before the step.
    /// A step that is not positive does not move. `maxOffset` is where the script ends.
    public static func tick(_ roll: inout Roll, _ dt: TimeInterval, at now: Date, hovered: Bool, maxOffset: Double) {
        if roll.phase == .countdown, let end = roll.countdownEndsAt, now >= end {
            roll.phase = .rolling
            roll.countdownEndsAt = nil
            roll.lastVoiceAt = now
        }
        guard isMoving(roll, at: now, hovered: hovered), dt > 0 else { return }
        roll.offset = min(roll.offset + roll.speed * dt, max(0, maxOffset))
        if maxOffset > 0, roll.offset >= maxOffset { roll.phase = .finished }
    }
}
