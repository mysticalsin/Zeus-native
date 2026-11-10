import Foundation

/// Timing for wake-word hands-free conversation (O20).
public enum WakeConversationTiming {
    public static let silenceAfterSpeech: TimeInterval = 90
    public static let silenceWhenEmpty: TimeInterval = 90
    public static let hardLimit: TimeInterval = 180
}
