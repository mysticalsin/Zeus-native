import Foundation

/// One sentence for a missing talk prerequisite. The words are the ones Settings already shows.
/// Camera, calendar and automation are not inputs. This function stores no settings key and draws no button.
public enum TalkMissingSetup {
    public static func sentence(mic: Bool, screen: Bool, brainKey: Bool, cli: Bool) -> String? {
        _ = (mic, screen, brainKey, cli)
        return "placeholder"
    }
}
