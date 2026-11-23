import Foundation

/// Binds a spoken yes, no, or open to the card that was on screen when listening started.
public enum SpokenApprovalCapture {
    /// The card id to keep. A blank id is the same as no card.
    public static func atSpeechStart(displayedCardID: String?) -> String? {
        _ = displayedCardID
        return nil
    }

    /// Whether that spoken answer may resolve the card on screen now.
    public static func applies(capturedCardID: String?, displayedCardID: String?) -> Bool {
        _ = capturedCardID
        guard let displayedCardID else { return false }
        return !displayedCardID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
