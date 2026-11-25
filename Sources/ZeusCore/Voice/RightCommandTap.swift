import Foundation

/// A solo tap of the right Command key toggles listening.
///
/// A tap is a right Command press that comes up within `maximumTap` without any other key
/// joining it. The left Command key, a chord, and a longer hold produce nothing.
///
/// Together with the Control+Option hold: while that hold is in progress a right Command tap
/// is discarded, so it cannot start or stop a second session. When the hold begins it takes
/// the one listening session (a tap that had already started stays "on"). When the hold ends
/// or aborts, the session is off, and the next right Command tap starts it again.
/// The cues are the same Superwhisper files as the hold, read at runtime, with the neutral
/// Mac sound when a file is missing. Reduce Motion does not silence them.
public struct RightCommandTap: Equatable, Sendable {
    /// Longer than this is a hold, not a tap.
    public static let maximumTap: TimeInterval = 0.30
    public static let rightKeyCode: UInt16 = 54
    public static let leftKeyCode: UInt16 = 55

    public enum Signal: Equatable, Sendable {
        case toggle(listening: Bool, cue: TalkCuePlay)
    }

    public private(set) var listening = false
    private var downSince: TimeInterval?
    private var spoiled = false
    /// Control+Option currently owns the keyboard. Right Command cannot toggle until it lets go.
    private var holdOwned = false

    public init() {}

    /// Audio is not motion. The flag is part of the signature so a caller cannot gate the cue on it.
    public static func playsAudio(reduceMotion: Bool) -> Bool {
        _ = reduceMotion
        return true
    }

    public mutating func rightDown(at time: TimeInterval, otherKeyDown: Bool) -> [Signal] {
        if holdOwned || otherKeyDown {
            spoiled = true
            downSince = nil
            return []
        }
        spoiled = false
        downSince = time
        return []
    }

    public mutating func rightUp(
        at time: TimeInterval,
        afterDownAt down: TimeInterval? = nil,
        reduceMotion: Bool = false,
        fileIsReadable: @Sendable (String) -> Bool = { _ in true }
    ) -> [Signal] {
        _ = reduceMotion
        if downSince == nil, let down, !spoiled, !holdOwned {
            downSince = down
        }
        defer {
            downSince = nil
            spoiled = false
        }
        guard !holdOwned, let since = downSince, !spoiled else { return [] }
        guard time >= since, time - since <= Self.maximumTap else { return [] }
        listening.toggle()
        let kind: TalkCueKind = listening ? .start : .end
        let cue = TalkCuePlay(kind: kind, source: TalkCueFiles.resolve(kind, readable: fileIsReadable))
        return [.toggle(listening: listening, cue: cue)]
    }

    /// Another key went down while right Command was down. This press is a modifier, not a tap.
    public mutating func otherKey() -> [Signal] {
        guard downSince != nil else { return [] }
        spoiled = true
        return []
    }

    public mutating func leftDown(at time: TimeInterval) -> [Signal] {
        _ = time
        return []
    }

    public mutating func leftUp(at time: TimeInterval) -> [Signal] {
        _ = time
        return []
    }

    /// The Control+Option hold is pending or talking. Drop a half-finished tap and do not toggle.
    public mutating func holdOwnsKeyboard() -> [Signal] {
        holdOwned = true
        downSince = nil
        spoiled = true
        return []
    }

    /// The hold returned to idle. A later solo tap can toggle again.
    public mutating func holdReleasedKeyboard() {
        holdOwned = false
        spoiled = false
        downSince = nil
    }

    /// The hold began or ended the one shared listening session.
    public mutating func noteSession(listening isListening: Bool) {
        listening = isListening
    }

    /// Permission or the voice path refused the start. The next tap starts, it does not stop.
    public mutating func noteStartRejected() {
        if listening { listening = false }
    }
}
