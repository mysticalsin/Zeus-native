import os

/// Signposts for the speech-to-text stages. Debug builds only, so a release app does not
/// emit them. Names are stage ids. Transcript text is never a signpost argument.
enum STTSignpost {
    private static let log = OSLog(subsystem: "app.zeus.mac", category: "stt")

    static func event(_ name: StaticString) {
        #if DEBUG
        os_signpost(.event, log: log, name: name)
        #endif
    }
}
