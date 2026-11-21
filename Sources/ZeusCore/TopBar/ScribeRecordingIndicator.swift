import Foundation

/// The closed-notch indicator while a meeting recording is open.
public enum ScribeRecordingIndicator {
    public static func feedback(for phase: String) -> (phase: String, label: String)? {
        switch phase {
        case "recording": ("recording", "Recording")
        case "ending": ("recording", "Ending the recording")
        default: nil
        }
    }
}
