import Foundation

/// What the Face presence card says while a face is being learned. A kept frame counts toward ten. A turned-down
/// frame says what to change, so the person is not left on "Look at the camera" when the sample was a photo, too
/// dark, or the same as the last one.
public enum EnrollmentCoach {
    public static func line(_ refusal: EnrollmentPlan.Refusal) -> String {
        switch refusal {
        case .noFace: "No face in view. Look at the camera."
        case .unreadable: "That frame could not be read. Hold still."
        case .otherRevision: "That frame does not match this enrollment."
        case .spoofed: "That looks like a photo or a screen. Use your face."
        case .weakAlignment: "Move so your whole face is in view."
        case .lowQuality: "The picture is too unclear. Face the light."
        case .tooSimilar: "Move a little. That frame matched the last one."
        }
    }

    /// "3 of 10." Counts below zero read as zero. Counts past the goal stay on the goal.
    public static func progress(accepted: Int) -> String {
        let count = min(max(accepted, 0), EnrollmentPlan.requiredSamples)
        return "\(count) of \(EnrollmentPlan.requiredSamples)."
    }

    /// The line to show under Enrolling. Blank text and every other state leave the status hint alone.
    public static func shown(enrolling: Bool, line: String?) -> String? {
        guard enrolling else { return nil }
        let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
