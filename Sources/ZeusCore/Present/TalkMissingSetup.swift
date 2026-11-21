import Foundation

/// One sentence for a missing talk prerequisite. The words are the ones Settings already shows.
/// Camera, calendar and automation are not inputs. This function stores no settings key and draws no button.
public enum TalkMissingSetup {
    /// Permissions, Microphone row, when access is denied.
    public static let microphoneSentence = "Denied. Turn it on in System Settings \u{203A} Privacy \u{203A} Microphone."
    /// Permissions, Screen Recording row, when access is denied.
    public static let screenSentence = "Denied. Turn it on in System Settings \u{203A} Privacy \u{203A} Screen Recording."
    /// Integrations row when the command-line tool is not on this Mac.
    public static let brainSentence = "Not found on this Mac. Install shows the official command."

    /// Microphone first, then the screen, then a brain with neither a key nor a command-line tool.
    /// A saved key or a command-line tool is enough for the brain. All present returns no sentence.
    public static func sentence(mic: Bool, screen: Bool, brainKey: Bool, cli: Bool) -> String? {
        if !mic { return microphoneSentence }
        if !screen { return screenSentence }
        if !brainKey && !cli { return brainSentence }
        return nil
    }
}
