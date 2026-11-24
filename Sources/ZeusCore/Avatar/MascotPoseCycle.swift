import Foundation

/// Poses a mascot state cycles through, and how long each slot lasts.
/// Pose names are `LivingPose` raw values. Travel, glance, and walk stay in the app.
public struct MascotPoseCycle: Equatable, Sendable {
    public var poses: [String]
    public var hold: Double

    public init(poses: [String], hold: Double) {
        self.poses = poses
        self.hold = hold
    }

    public static func cycle(for state: String) -> MascotPoseCycle {
        switch state {
        case "idle": MascotPoseCycle(poses: ["idle"], hold: 4)
        case "listening": MascotPoseCycle(poses: ["listening"], hold: 3)
        case "thinking": MascotPoseCycle(poses: ["thinking", "curious"], hold: 3.2)
        case "speaking": MascotPoseCycle(poses: ["welcome", "guiding"], hold: 1.8)
        case "pointing": MascotPoseCycle(poses: ["guiding"], hold: 2)
        case "clicking": MascotPoseCycle(poses: ["working", "organizing"], hold: 2.4)
        case "typing": MascotPoseCycle(poses: ["typing"], hold: 2.4)
        case "browsing": MascotPoseCycle(poses: ["searching", "curious"], hold: 2.4)
        case "agent": MascotPoseCycle(poses: ["working", "typing", "searching", "organizing", "carrying"], hold: 2.4)
        case "approval": MascotPoseCycle(poses: ["approval_wait"], hold: 4)
        case "error": MascotPoseCycle(poses: ["error", "confused"], hold: 2)
        case "done": MascotPoseCycle(poses: ["success", "celebrate"], hold: 1.8)
        case "teleprompter": MascotPoseCycle(poses: ["guiding", "curious"], hold: 3)
        default: MascotPoseCycle(poses: ["idle"], hold: 4)
        }
    }
}
