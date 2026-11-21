import Foundation

/// What the playback graph does when the output device or its format changes.
public enum PlaybackGraphRecovery {
    public static func afterConfigurationChange() -> (rewire: Bool, reportLineFinished: Bool) {
        (true, false)
    }
}

/// Whether Scribe's system tap is still pointed at the output the person hears.
public enum ScribeOutputRoute {
    public static func shouldRebuild(capturedUID: String?, currentUID: String?) -> Bool {
        guard let currentUID, !currentUID.isEmpty else { return false }
        return capturedUID != currentUID
    }

    public static func rejectsZeroSampleRate(_ rate: Double) -> Bool {
        !(rate.isFinite && rate > 0)
    }
}
