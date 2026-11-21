import Foundation

/// Order of work for one playback buffer.
public enum OrbBandWork {
    public enum Step: String, Equatable, Sendable {
        case queuePlayback
        case analyseBands
    }

    /// The band maths still runs before the buffer is queued.
    public static func steps(personaIsOrb: Bool) -> [Step] {
        personaIsOrb ? [.analyseBands, .queuePlayback] : [.queuePlayback]
    }
}
