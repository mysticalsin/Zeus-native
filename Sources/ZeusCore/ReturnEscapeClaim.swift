import Foundation

/// Return and Escape belong to one card. While the dictation check is up, the meeting card does not take the keyboard.
public enum ReturnEscapeClaim {
    public static func meetingCardCanBecomeKey(dictationCheckVisible: Bool) -> Bool {
        !dictationCheckVisible
    }
}
