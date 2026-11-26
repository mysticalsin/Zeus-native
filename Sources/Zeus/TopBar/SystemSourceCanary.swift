/// One now-playing entry for the system-source canary, and the clear that takes it down.
///
/// The title is the word Zeus. The album field holds the token. Playback is playing.
/// `reduce` is the only way to change the slot. A publish command is the only command
/// that fills it. Locked, asleep, and an inactive session each leave the slot empty.
/// An entry that has been up for the hold limit is cleared. On macOS the public
/// MediaPlayer center is written from this file, and only for a show or a remove.
public enum SystemSourceCanary {
    /// The word the system display shows as the title.
    public static let title = "Zeus"
    /// Playing. The live center writes this rate as a number.
    public static let playingRate = 1
    /// A published entry stays up for fewer than this many whole seconds.
    public static let holdLimitSeconds = 3
    /// The album token is lowercase hex of at most this many bytes, the helper line's own cap.
    public static let tokenByteLimit = 256

    public enum Refusal: String, Sendable, Equatable {
        case locked
        case asleep
        case sessionInactive
        case token
        case alreadyPublished
    }

    /// The three gates the canary reads. A publish needs the screen unlocked, the Mac awake,
    /// and this session on the console.
    public struct Gates: Sendable, Equatable {
        public var locked: Bool
        public var asleep: Bool
        public var sessionActive: Bool

        public init(locked: Bool, asleep: Bool, sessionActive: Bool) {
            self.locked = locked
            self.asleep = asleep
            self.sessionActive = sessionActive
        }

        public static let open = Gates(locked: false, asleep: false, sessionActive: true)
    }

    /// The one entry. It carries the title, the token, and the playing rate.
    public struct Slot: Sendable, Equatable {
        public var title: String
        public var album: String
        public var playbackRate: Int

        public init(title: String, album: String, playbackRate: Int) {
            self.title = title
            self.album = album
            self.playbackRate = playbackRate
        }
    }

    public enum Command: Sendable, Equatable {
        case publish(token: String, gates: Gates)
        case clear
        case hold(seconds: Int)
    }

    /// What the system display should do after `reduce`. A refusal and a hold under the limit
    /// leave the center untouched.
    public enum DisplayEffect: Sendable, Equatable {
        case show(Slot)
        case remove
        case none
    }

    public struct State: Sendable, Equatable {
        public var slot: Slot?
        public var refusal: Refusal?

        public init() {
            slot = nil
            refusal = nil
        }
    }

    public static func reduce(_ state: State, _ command: Command) -> State {
        var next = state
        switch command {
        case .publish(let token, let gates):
            if state.slot != nil {
                next.refusal = .alreadyPublished
                return next
            }
            if let refusal = gateRefusal(gates) {
                next.refusal = refusal
                return next
            }
            guard let slot = slot(token: token) else {
                next.refusal = .token
                return next
            }
            next.slot = slot
            next.refusal = nil
        case .clear:
            guard state.slot != nil else { return state }
            next.slot = nil
            next.refusal = nil
        case .hold(let seconds):
            guard state.slot != nil, seconds >= holdLimitSeconds else { return state }
            next.slot = nil
            next.refusal = nil
        }
        return next
    }

    public static func displayEffect(before: State, _ command: Command, after: State) -> DisplayEffect {
        switch command {
        case .publish:
            guard before.slot == nil, let slot = after.slot else { return .none }
            return .show(slot)
        case .clear, .hold:
            guard before.slot != nil, after.slot == nil else { return .none }
            return .remove
        }
    }

    /// The entry a token would show. A token outside the hex rule has no entry.
    public static func slot(token: String) -> Slot? {
        guard acceptedToken(token) else { return nil }
        return Slot(title: title, album: token, playbackRate: playingRate)
    }

    private static func gateRefusal(_ gates: Gates) -> Refusal? {
        if gates.locked { return .locked }
        if gates.asleep { return .asleep }
        if !gates.sessionActive { return .sessionInactive }
        return nil
    }

    /// Lowercase hex, one byte at least, and at most `tokenByteLimit` bytes.
    private static func acceptedToken(_ token: String) -> Bool {
        let count = token.utf8.count
        guard count > 0, count <= tokenByteLimit else { return false }
        return token.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
        }
    }
}

#if os(macOS)
import MediaPlayer

extension SystemSourceCanary {
    /// Writes a show or a remove through the public now-playing center. `.none` leaves it alone.
    public enum Display {
        public static func apply(_ effect: DisplayEffect) {
            switch effect {
            case .none:
                return
            case .remove:
                let center = MPNowPlayingInfoCenter.default()
                center.nowPlayingInfo = nil
                center.playbackState = .stopped
            case .show(let slot):
                let center = MPNowPlayingInfoCenter.default()
                center.playbackState = .playing
                center.nowPlayingInfo = [
                    MPMediaItemPropertyTitle: slot.title,
                    MPMediaItemPropertyAlbumTitle: slot.album,
                    MPNowPlayingInfoPropertyPlaybackRate: Double(slot.playbackRate),
                ]
            }
        }
    }
}
#endif
