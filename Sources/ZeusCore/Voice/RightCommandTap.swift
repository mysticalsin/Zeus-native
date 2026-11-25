import Foundation

/// A solo tap of the right Command key asks for Murmur and nothing else.
///
/// A tap comes up within `maximumTap` with no other key. Left Command, a chord, and a
/// longer hold produce nothing. Talk is not this key. While a talk hold owns the
/// keyboard the tap is discarded, so one press cannot open a second session.
public struct RightCommandTap: Equatable, Sendable {
    /// Longer than this is a hold, not a tap.
    public static let maximumTap: TimeInterval = KeyActionRouter.commandTapMax
    public static let rightKeyCode: UInt16 = 54
    public static let leftKeyCode: UInt16 = 55

    public enum Signal: Equatable, Sendable {
        /// The dictation path is the only owner of this signal.
        case murmur
    }

    /// True only when a talk hold has told this tap that talk is listening. A Right Command tap never sets it.
    public private(set) var listening = false
    private var router = KeyActionRouter()
    /// A talk hold is in progress. Right Command cannot start Murmur until it lets go.
    private var holdOwned = false

    public init() {}

    /// Audio is not motion. The flag is part of the signature so a caller cannot gate a cue on it.
    public static func playsAudio(reduceMotion: Bool) -> Bool {
        _ = reduceMotion
        return true
    }

    public mutating func rightDown(at time: TimeInterval, otherKeyDown: Bool) -> [Signal] {
        guard !holdOwned else {
            _ = router.send(.cancel)
            return []
        }
        return map(router.send(.rightCommand(down: true, at: time, otherKeyDown: otherKeyDown)))
    }

    public mutating func rightUp(
        at time: TimeInterval,
        afterDownAt down: TimeInterval? = nil,
        reduceMotion: Bool = false,
        fileIsReadable: @Sendable (String) -> Bool = { _ in true }
    ) -> [Signal] {
        _ = reduceMotion
        _ = fileIsReadable
        if holdOwned {
            _ = router.send(.hardwareRightCommandUp(at: time))
            return []
        }
        if case .idle = router.phase, let down {
            _ = router.send(.rightCommand(down: true, at: down, otherKeyDown: false))
        }
        return map(router.send(.rightCommand(down: false, at: time, otherKeyDown: false)))
    }

    /// Another key went down while right Command was down. This press is not a tap.
    public mutating func otherKey() -> [Signal] {
        map(router.send(.otherKey(at: 0)))
    }

    public mutating func leftDown(at time: TimeInterval) -> [Signal] {
        map(router.send(.leftCommand(down: true, at: time)))
    }

    public mutating func leftUp(at time: TimeInterval) -> [Signal] {
        map(router.send(.leftCommand(down: false, at: time)))
    }

    /// The key-up never arrived. The next down is a new press, and this one does not start Murmur.
    public mutating func hardwareRightCommandUp(at time: TimeInterval) -> [Signal] {
        map(router.send(.hardwareRightCommandUp(at: time)))
    }

    /// Talk owns the keyboard. Drop a half-finished tap.
    public mutating func holdOwnsKeyboard() -> [Signal] {
        holdOwned = true
        return map(router.send(.cancel))
    }

    /// Talk returned to idle. A later solo tap can ask for Murmur again.
    public mutating func holdReleasedKeyboard() {
        holdOwned = false
    }

    /// Talk began or ended. Recorded so a caller can read it. A tap does not change it.
    public mutating func noteSession(listening isListening: Bool) {
        listening = isListening
    }

    /// A refused start must not look like talk is on.
    public mutating func noteStartRejected() {
        if listening { listening = false }
    }

    private func map(_ actions: [KeyActionRouter.Action]) -> [Signal] {
        var signals: [Signal] = []
        for action in actions {
            switch action {
            case .murmur:
                signals.append(.murmur)
            case .talk:
                break
            }
        }
        return signals
    }
}
