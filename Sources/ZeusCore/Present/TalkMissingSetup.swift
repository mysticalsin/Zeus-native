import Foundation

/// One sentence for a missing talk prerequisite. The words are the ones Settings already shows.
/// Camera, calendar and automation are not inputs. This function stores no settings key and draws no button.
public enum TalkMissingSetup {
    /// Permissions, Microphone row, when access is denied.
    public static let microphoneSentence = "Denied. Turn it on in System Settings \u{203A} Privacy \u{203A} Microphone."
    /// Permissions, Screen Recording row, when access is denied.
    public static let screenSentence = "Denied. Turn it on in System Settings \u{203A} Privacy \u{203A} Screen Recording."
    /// Integrations row when the command-line tool is not on this Mac.
    public static let cliSentence = "Not found on this Mac. Install shows the official command."
    /// Engine row when no key is saved.
    public static let keySentence = "No key saved. Commands go to the assistant."

    /// Microphone, then the screen, then the key, then the command-line tool. Each gap has its own sentence.
    public static func sentences(mic: Bool, screen: Bool, brainKey: Bool, cli: Bool) -> [String] {
        var lines: [String] = []
        if !mic { lines.append(microphoneSentence) }
        if !screen { lines.append(screenSentence) }
        if !brainKey { lines.append(keySentence) }
        if !cli { lines.append(cliSentence) }
        return lines
    }

    /// The first gap, in the same order as `sentences`. No gap returns nil.
    public static func sentence(mic: Bool, screen: Bool, brainKey: Bool, cli: Bool) -> String? {
        sentences(mic: mic, screen: screen, brainKey: brainKey, cli: cli).first
    }
}
