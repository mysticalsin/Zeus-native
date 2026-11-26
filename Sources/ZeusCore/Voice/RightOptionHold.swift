import Foundation

/// Right Option press-and-hold: the bar appears at the key-down, and listening starts once that hold is still alone.
///
/// Right Option types accents, so a letter inside `listenConfirm` never opens the microphone. That window is
/// `VoiceKey.secondKeyConfirm`. The bar does not wait for it. A hold that is still alone when the window ends listens.
public struct RightOptionHold: Equatable, Sendable {
    /// Carbon virtual key code for the right Option key.
    public static let rightKeyCode: UInt16 = 61
    /// The bar is requested in the same turn as the key-down. It does not wait out the typing window.
    public static let appearLatency: TimeInterval = 0
    /// How long Right Option must stay alone before the microphone opens. A letter inside this time is typing.
    public static var listenConfirm: TimeInterval { VoiceKey.secondKeyConfirm }

    public enum Phase: Equatable, Sendable {
        case idle
        case shown(since: TimeInterval)
        case listening(since: TimeInterval)
    }

    public enum Action: Equatable, Sendable {
        /// The hold HUD appears now. The microphone stays closed.
        case showBar
        /// The hold ended or a letter joined before listening. Take the HUD down.
        case hideBar
        /// The hold is still alone after the typing window. Open the microphone.
        case listen
        /// The microphone was open and the hold is over, or a letter joined it.
        case stopListening
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    /// The keyboard after one event. `ordinaryKeys` are the non-modifier keys that are down.
    /// `confirm` is the typing window. The talk monitor passes the same value the voice machine waits.
    public mutating func observe(deviceKeys: Set<UInt16>, ordinaryKeys: Set<UInt16>, at time: TimeInterval,
                                 confirm: TimeInterval = listenConfirm) -> [Action] {
        let down = deviceKeys.contains(Self.rightKeyCode)
        let alone = Self.isAlone(deviceKeys: deviceKeys, ordinaryKeys: ordinaryKeys)
        switch phase {
        case .idle:
            guard down, alone else { return [] }
            phase = .shown(since: time)
            return [.showBar]
        case .shown(let since):
            guard down, alone else {
                phase = .idle
                return [.hideBar]
            }
            guard time + 0.001 >= since + confirm else { return [] }
            phase = .listening(since: since)
            return [.listen]
        case .listening:
            guard down, alone else {
                phase = .idle
                return [.stopListening]
            }
            return []
        }
    }

    /// Right Option is no longer the second talk key. A bar that was only shown comes down. A listen already
    /// opened belongs to the voice machine, which ends that turn when the key changes.
    public mutating func disarm() -> [Action] {
        switch phase {
        case .idle, .listening:
            phase = .idle
            return []
        case .shown:
            phase = .idle
            return [.hideBar]
        }
    }

    /// Right Option is the only device key down, and no letter or other ordinary key is down with it.
    public static func isAlone(deviceKeys: Set<UInt16>, ordinaryKeys: Set<UInt16>) -> Bool {
        deviceKeys == [rightKeyCode] && ordinaryKeys.isEmpty
    }
}
