import Foundation

/// Right Option strict push-to-talk.
///
/// Key-down starts listening and key-up stops it. A tap never latches, a repeated key-down
/// does not toggle, and another key does not cancel. Left Option does nothing. A yield that
/// already belongs to Chat, pointing, dictation, Polyglot, or VoiceOver keeps the key quiet.
/// If focus changes before the key-up arrives, listening stops and stays stopped until the
/// key is seen up.
public struct RightOptionPushToTalk: Equatable, Sendable {
    /// Physical Right Option. Left Option is 58.
    public static let rightKeyCode: UInt16 = 61
    public static let leftKeyCode: UInt16 = 58

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
        case rightOption(down: Bool, otherTurnOpen: Bool)
        /// Left Option changed. It never starts, stops, or toggles.
        case leftOption(down: Bool)
        /// Some other key changed. It does not cancel and it does not toggle.
        case otherKey
        /// Focus moved and the key-up may never arrive.
        case focusChanged
    }

    public var yieldedTo: Yield?
    public private(set) var phase: Phase = .idle

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

    public mutating func send(_ event: Event) -> [Effect] {
        switch event {
        case .leftOption, .otherKey:
            return []
        case .focusChanged:
            guard phase == .listening else { return [] }
            phase = .quiet
            return [.stop]
        case .rightOption(let down, let otherTurnOpen):
            if down {
                guard phase == .idle else { return [] }
                if yieldedTo != nil || otherTurnOpen {
                    phase = .quiet
                    return []
                }
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
}
