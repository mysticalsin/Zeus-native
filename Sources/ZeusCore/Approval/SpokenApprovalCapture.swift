import Foundation

/// Binds a spoken yes, no, or open to the card that was on screen when listening started.
public enum SpokenApprovalCapture {
    /// The card id to keep. A blank id is the same as no card.
    public static func atSpeechStart(displayedCardID: String?) -> String? {
        guard let displayedCardID else { return nil }
        let trimmed = SpokenApprovalCaptureBox.trimmedCardID(displayedCardID)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Whether that spoken answer may resolve the card on screen now.
    public static func applies(capturedCardID: String?, displayedCardID: String?) -> Bool {
        guard let capturedCardID, let displayedCardID else { return false }
        return capturedCardID == displayedCardID
    }
}
