import CoreGraphics
import Foundation

/// Which display a talk turn may capture, and whether a shot that is already ready
/// may ride with speech. Pure: no capture session and no ScreenCaptureKit.
public enum TalkCapturePolicy {
    public static let sttCapMs = 450

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
        public var lateRelativeToCap: Bool

        public init(includeShot: Bool, speechStarts: Bool, lateRelativeToCap: Bool) {
            self.includeShot = includeShot
            self.speechStarts = speechStarts
            self.lateRelativeToCap = lateRelativeToCap
        }
    }

    public static func displayIDs(seeing: Bool, pointer: CGPoint, displays: [Display]) -> [UInt32] {
        displays.map(\.id)
    }

    public static func decision(shotReadyMs: Int, sttFinalMs: Int?, capMs: Int = sttCapMs) -> Decision {
        Decision(includeShot: false, speechStarts: false, lateRelativeToCap: false)
    }
}
