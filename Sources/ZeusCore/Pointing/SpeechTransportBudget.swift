import Foundation

/// How long a speech request may run in total.
/// The 20 s and 45 s request timeouts stay as they are. This only decides the resource cap.
public enum SpeechTransportBudget {
    /// Red: a 20 s request is raised to 180 s, so a trickle of bytes outlives the request timeout.
    public static func resourceTimeout(request: TimeInterval) -> TimeInterval {
        max(request, 180)
    }
}
