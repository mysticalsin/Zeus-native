import Foundation

/// Control+Option hold-to-talk, as a pure state machine.
///
/// Input is a modifier set plus a timestamp (a `flagsChanged` chord, not a key). Output is
/// begin/end for the existing voice pipeline, plus when to preload and when the debounce timer
/// should fire. Option alone never matches, so typing special characters is left alone.
///
/// Cue pairing: a hold that ends or is cancelled before `debounce` plays neither cue. A hold that
/// begins plays the start cue once; the matching release plays the end cue once, and a cancel
/// after begin plays the end cue once as well (the voice turn is aborted, not sent).
public struct TalkHold: Equatable, Sendable {
    public static let debounce: TimeInterval = 0.15

    public enum Phase: Equatable, Sendable {
        case idle
        case pending(since: TimeInterval)
        case talking
    }

    public enum Signal: Equatable, Sendable {
        /// Both modifiers are down. Cache the cues during the debounce so begin is not waiting on disk.
        case preload
        case schedule(at: TimeInterval)
        case cancelSchedule
        /// Debounce elapsed while Control+Option was still held.
        case begin
        /// A modifier was released after begin. Send the turn and play the end cue.
        case end
        /// Another key joined after begin. Do not send; still play the end cue so the pair closes.
        case abort
    }

    public private(set) var phase: Phase = .idle
    /// After a cancel, the chord is still physically down. Do not start again until it has been released.
    private var suppressUntilRelease = false

    public init() {}

    /// `flagsChanged`. Exact Control+Option arms the hold. Anything else, including Option alone,
    /// releases it.
    public mutating func flags(_ modifiers: TalkModifiers, at time: TimeInterval) -> [Signal] {
        if suppressUntilRelease {
            guard modifiers != .controlOption else { return [] }
            suppressUntilRelease = false
        }
        let exact = modifiers == .controlOption
        switch phase {
        case .idle:
            guard exact else { return [] }
            phase = .pending(since: time)
            return [.preload, .schedule(at: time + Self.debounce)]
        case .pending:
            guard !exact else { return [] }
            phase = .idle
            return [.cancelSchedule]
        case .talking:
            guard !exact else { return [] }
            phase = .idle
            return [.end]
        }
    }

    /// The debounce timer. Begins only if Control+Option is still the pending chord.
    public mutating func advance(at time: TimeInterval) -> [Signal] {
        guard case .pending(let since) = phase else { return [] }
        guard time + 0.000_001 >= since + Self.debounce else { return [] }
        phase = .talking
        return [.begin]
    }

    /// A key joined the chord, VoiceOver took the modifiers, or the hold was abandoned.
    /// Before begin: neither cue. After begin: one end cue, and the turn is not sent.
    public mutating func cancel() -> [Signal] {
        suppressUntilRelease = true
        switch phase {
        case .idle:
            return []
        case .pending:
            phase = .idle
            return [.cancelSchedule]
        case .talking:
            phase = .idle
            return [.abort]
        }
    }
}

/// Modifier flags the hold machine understands. Distinct from `ShortcutModifiers` so the machine
/// stays free of AppKit and of the other shortcut bindings.
public struct TalkModifiers: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = TalkModifiers(rawValue: 1)
    public static let option = TalkModifiers(rawValue: 2)
    public static let shift = TalkModifiers(rawValue: 4)
    public static let command = TalkModifiers(rawValue: 8)
    public static let function = TalkModifiers(rawValue: 16)

    public static let controlOption: TalkModifiers = [.control, .option]
}

public enum TalkCueKind: String, Equatable, Sendable {
    case start
    case end
}

public enum TalkCueSource: Equatable, Sendable {
    /// An absolute file read at runtime. Never bundled.
    case file(String)
    case system(String)
}

/// The two talk cues, in one place. These are Tony's installed Superwhisper classic files.
/// Read them only at runtime. Do not copy, embed, or bundle them.
public enum TalkCueFiles {
    public static let startPath = "/Applications/superwhisper.app/Contents/Resources/StartClassic.m4a"
    public static let endPath = "/Applications/superwhisper.app/Contents/Resources/StopClassic.m4a"
    /// Neutral macOS sound used when a file is missing or unreadable. Logged by the player.
    public static let fallbackSystemSound = "Tink"

    public static func path(_ kind: TalkCueKind) -> String {
        switch kind {
        case .start: startPath
        case .end: endPath
        }
    }

    public static func resolve(_ kind: TalkCueKind, readable: (String) -> Bool) -> TalkCueSource {
        let path = path(kind)
        if readable(path) { return .file(path) }
        return .system(fallbackSystemSound)
    }
}

public struct TalkCuePlay: Equatable, Sendable {
    public var kind: TalkCueKind
    public var source: TalkCueSource

    public init(kind: TalkCueKind, source: TalkCueSource) {
        self.kind = kind
        self.source = source
    }
}

/// What one hold would play. Reduce Motion is accepted and ignored: cues are not animation.
public struct TalkRehearsal: Sendable {
    public private(set) var hold = TalkHold()
    public private(set) var plays: [TalkCuePlay] = []
    public private(set) var preloaded = false
    public var fileIsReadable: (String) -> Bool

    public init(fileIsReadable: @escaping (String) -> Bool = { _ in true }) {
        self.fileIsReadable = fileIsReadable
    }

    /// Audio is not motion. The flag is part of the signature so a caller cannot gate the cue on it.
    public static func playsAudio(reduceMotion: Bool) -> Bool {
        _ = reduceMotion
        return true
    }

    public mutating func flags(_ modifiers: TalkModifiers, at time: TimeInterval, reduceMotion: Bool = false) {
        _ = reduceMotion
        apply(hold.flags(modifiers, at: time))
    }

    public mutating func advance(at time: TimeInterval, reduceMotion: Bool = false) {
        _ = reduceMotion
        apply(hold.advance(at: time))
    }

    public mutating func cancel(reduceMotion: Bool = false) {
        _ = reduceMotion
        apply(hold.cancel())
    }

    private mutating func apply(_ signals: [TalkHold.Signal]) {
        for signal in signals {
            switch signal {
            case .preload:
                preloaded = true
            case .schedule, .cancelSchedule:
                break
            case .begin:
                plays.append(TalkCuePlay(kind: .start, source: TalkCueFiles.resolve(.start, readable: fileIsReadable)))
            case .end, .abort:
                plays.append(TalkCuePlay(kind: .end, source: TalkCueFiles.resolve(.end, readable: fileIsReadable)))
            }
        }
    }
}
