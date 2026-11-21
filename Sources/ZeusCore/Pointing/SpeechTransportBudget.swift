import Foundation

/// How long a speech request may run in total.
/// The 20 s and 45 s request timeouts stay as they are. This only decides the resource cap.
public enum SpeechTransportBudget {
    /// The resource cap is the request timeout. A 20 s request stays 20 s.
    public static func resourceTimeout(request: TimeInterval) -> TimeInterval {
        request
    }
}
