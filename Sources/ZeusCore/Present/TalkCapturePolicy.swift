import CoreGraphics
import Foundation

/// Which display a talk turn may capture, and whether a shot that is already ready
/// may ride with speech. Pure: no capture session and no ScreenCaptureKit.
public enum TalkCapturePolicy {
    /// Speech starts by this time even when the shot is not ready.
    public static let sttCapMs = 450
    /// A shot with this many milliseconds or fewer left before the cap is late.
    /// 400 ms against a 450 ms cap is the first millisecond of that window.
    static let lateWindowMs = 50

    public struct Display: Equatable, Sendable {
        public var id: UInt32
        public var frame: CGRect

        public init(id: UInt32, frame: CGRect) {
            self.id = id
            self.frame = frame
        }
    }

    public struct Decision: Equatable, Sendable {
        public var includeShot: Bool
        public var speechStarts: Bool
        /// True when the shot is ready inside the last `lateWindowMs` of the cap, or after the cap.
        public var lateRelativeToCap: Bool

        public init(includeShot: Bool, speechStarts: Bool, lateRelativeToCap: Bool) {
            self.includeShot = includeShot
            self.speechStarts = speechStarts
            self.lateRelativeToCap = lateRelativeToCap
        }
    }

    /// Seeing off captures nothing. Seeing on returns only the display id under the pointer.
    /// A pointer on no display captures nothing. Other displays are not added.
    public static func displayIDs(seeing: Bool, pointer: CGPoint, displays: [Display]) -> [UInt32] {
        guard seeing, let hit = displays.last(where: { $0.frame.contains(pointer) }) else { return [] }
        return [hit.id]
    }

    /// `sttFinalMs` is when the transcript final arrives. Nil means it has not arrived, so speech
    /// starts at the cap. A shot ready at or before that moment may be included, unless it is late
    /// relative to the cap. Speech starts either way.
    public static func decision(shotReadyMs: Int, sttFinalMs: Int?, capMs: Int = sttCapMs) -> Decision {
        let cap = max(capMs, 0)
        let speechAt = min(max(sttFinalMs ?? cap, 0), cap)
        let late = shotReadyMs >= cap - lateWindowMs
        let include = shotReadyMs >= 0 && shotReadyMs <= speechAt && !late
        return Decision(includeShot: include, speechStarts: true, lateRelativeToCap: late)
    }
}
