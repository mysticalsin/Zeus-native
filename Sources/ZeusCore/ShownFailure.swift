import Foundation

/// Sentences a person can act on. The system error stays in the log.
public enum ShownFailure {
    public static let meetingSave = "Couldn't save this meeting. It is still here. Try again."
    public static let meetingNotes = "The notes couldn't be written, so only the transcript was saved."
    public static let dictationFile = "Couldn't read that file. Try another one."

    public static func engine(_ name: String) -> String {
        "\(name) couldn't transcribe that. Try again."
    }
}
