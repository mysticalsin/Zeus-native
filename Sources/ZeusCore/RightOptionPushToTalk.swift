import Foundation

/// Right Option strict push-to-talk.
///
/// Key-down starts listening and key-up stops it. A tap never latches, a repeated key-down
/// does not toggle, and another key does not cancel. Left Option does nothing. A yield that
/// already belongs to Chat, pointing, dictation, Polyglot, or VoiceOver keeps the key quiet.
/// A missed key-up is the live modifier flags, read on any later event and on the 3 s look.
/// The hold also ends at the existing talk limit, on a screen lock, and when secure input is on
/// or unknown.
public struct RightOptionPushToTalk: Equatable, Sendable {
    /// Physical Right Option. Left Option is 58.
    public static let rightKeyCode: UInt16 = 61
    public static let leftKeyCode: UInt16 = 58
    /// The same 45 s window a talk turn already uses. Not a new timeout.
    public static var holdCap: TimeInterval { FastTier.conversationWindowSeconds }

    /// The listen chime is playback. It may play only after capture has started.
    /// Playing it first pulls a Bluetooth headset into its speaker profile, so the
    /// microphone opens later and the words said during that switch are gone.
    public enum ListenCue {
        public static func mayPlay(captureStarted: Bool) -> Bool { captureStarted }
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case listening
        /// The key may still be down. Listening is off, and another down does not start it.
        case quiet
    }

    public enum Effect: Equatable, Sendable {
        case start
        case stop
    }

    /// The holders `VoiceKey.secondTalkKey` already names. Talk to Zeus is not one of these:
    /// when Right Option is the talk key, this machine is that key.
    public enum Yield: Equatable, Sendable, Hashable {
        case chat
        case pointing
        case dictation
        case polyglot
        case voiceOver
    }

    public enum Event: Equatable, Sendable {
        /// Right Option changed. `otherTurnOpen` is true when another talk turn is already open.
        case rightOption(down: Bool, at: TimeInterval, otherTurnOpen: Bool)
        /// Left Option changed. It never starts, stops, or toggles.
        case leftOption(down: Bool)
        /// Some other key changed. It does not cancel and it does not toggle.
        case otherKey
        /// Focus moved and the key-up may never arrive. The adapter uses the global flags for this, not the app resigning.
        case focusChanged
        /// Global modifier flags. Nil means this read did not answer. Option absent is a lost key-up.
        case liveFlags(ShortcutModifiers?, at: TimeInterval)
        /// One look from the 3 s tick. Same flags, and the hold cap.
        case look(at: TimeInterval, flags: ShortcutModifiers?)
        /// Secure input. Nil or true stops. False leaves the hold.
        case secureInput(Bool?)
        /// The screen locked without the machine sleeping.
        case screenLocked
    }

    public var yieldedTo: Yield?
    public private(set) var phase: Phase = .idle
    /// When the current hold started. The cap is measured from here.
    public private(set) var startedAt: TimeInterval = 0

    public init() {}

    public static func yield(named name: String?) -> Yield? {
        switch name {
        case "Chat": .chat
        case "Pointing": .pointing
        case "Dictation": .dictation
        case "Polyglot": .polyglot
        case "VoiceOver": .voiceOver
        default: nil
        }
    }

    /// The status line. Right Option is hold to talk, release to stop. Another talk key still says double-tap to latch.
    public static func hint(talk: Shortcut, second: Shortcut?, dictationOn: Bool, dictation: Shortcut?) -> String {
        if talk == .rightOption {
            var line = "hold to talk, release to stop"
            if dictationOn, dictation != talk {
                line += "; dictation: " + (dictation.map { "hold \($0.title)" } ?? "off")
            }
            return line
        }
        if dictationOn, dictation == talk {
            return "double-tap \(talk.title) to talk, hold it to dictate"
        }
        var line = "hold \(talk.title) to talk, double-tap to latch"
        if let second {
            line += second == .rightOption ? " (or hold to talk, release to stop)" : " (or hold \(second.title))"
        }
        if dictationOn {
            line += "; dictation: " + (dictation.map { "hold \($0.title)" } ?? "off")
        }
        return line
    }

    public mutating func send(_ event: Event) -> [Effect] {
        switch event {
        case .leftOption, .otherKey:
            return []
        case .focusChanged, .screenLocked:
            return stopIfListening()
        case .secureInput(let enabled):
            guard phase == .listening else { return [] }
            if enabled == false { return [] }
            return stopIfListening()
        case .liveFlags(let flags, let at):
            return judge(at: at, flags: flags)
        case .look(let at, let flags):
            return judge(at: at, flags: flags)
        case .rightOption(let down, let at, let otherTurnOpen):
            if down {
                guard phase == .idle else { return [] }
                if yieldedTo != nil || otherTurnOpen {
                    phase = .quiet
                    return []
                }
                startedAt = at
                phase = .listening
                return [.start]
            }
            switch phase {
            case .listening:
                phase = .idle
                return [.stop]
            case .quiet:
                phase = .idle
                return []
            case .idle:
                return []
            }
        }
    }

    /// The owner refused the start. The key may still be down, so release stops nothing.
    public mutating func refuseStart() {
        if phase == .listening { phase = .quiet }
    }

    private mutating func judge(at time: TimeInterval, flags: ShortcutModifiers?) -> [Effect] {
        guard phase == .listening else { return [] }
        if time - startedAt >= Self.holdCap { return stopIfListening() }
        // The sample taken with the key-down is not a missed key-up. A later sample with Option
        // absent is. This is what keeps a press-and-hold listening when the global flags lag the event.
        guard time > startedAt else { return [] }
        if let flags, !flags.contains(.option) { return stopIfListening() }
        return []
    }

    private mutating func stopIfListening() -> [Effect] {
        guard phase == .listening else { return [] }
        phase = .quiet
        return [.stop]
    }
}
