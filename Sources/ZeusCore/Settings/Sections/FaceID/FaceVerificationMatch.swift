import Foundation

/// Distance and spoof rules for an approval. A cue can only refuse a frame.
public enum FaceVerificationMatch {
    public static func accepts(distance: Float) -> Bool {
        distance.isFinite && distance >= 0 && distance <= FaceVerificationPolicy.acceptDistance
    }

    public static func accepts(observation: [Float], enrolled: [Float]) -> Bool {
        accepts(distance: FaceMatch.distance(observation, enrolled))
    }

    /// A photo cue, a screen-shaped rectangle, or a virtual camera refuses the frame even when the vector is exact.
    public static func acceptFrame(distance: Float, spoof: Set<SpoofCue>, virtualCamera: Bool) -> Bool {
        if virtualCamera || !spoof.isEmpty { return false }
        return accepts(distance: distance)
    }
}
