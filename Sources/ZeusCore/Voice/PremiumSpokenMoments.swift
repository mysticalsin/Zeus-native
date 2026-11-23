import Foundation

/// Lines for premium surfaces that otherwise only draw. The app speaks a returned line with the
/// existing Zeus voice. This type does not play audio, open a microphone, or capture the screen.
public enum PremiumSpokenMoment: String, CaseIterable, Sendable, Identifiable {
    case recordingCountdown
    case notesReady
    case recordingSaved

    public var id: String { rawValue }

    public var settingKey: String {
        switch self {
        case .recordingCountdown: "voice.speakRecordingCountdown"
        case .notesReady: "voice.speakNotesReady"
        case .recordingSaved: "voice.speakRecordingSaved"
        }
    }

    public var settingTitle: String {
        switch self {
        case .recordingCountdown: "Speak the recording countdown"
        case .notesReady: "Speak when notes are ready"
        case .recordingSaved: "Speak when a recording is saved"
        }
    }

    public var settingDetail: String {
        switch self {
        case .recordingCountdown: "Zeus says three, two, one, then recording. Off until you turn it on, so a screen recording stays quiet."
        case .notesReady: "Zeus says the notes are ready when a meeting finishes."
        case .recordingSaved: "Zeus says saved when a screen recording is kept."
        }
    }

    /// The countdown stays off so it is not caught in a recording. The other two speak until turned off.
    public var defaultEnabled: Bool {
        switch self {
        case .recordingCountdown: false
        case .notesReady, .recordingSaved: true
        }
    }

    public static func isEnabled(_ moment: PremiumSpokenMoment, defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: moment.settingKey) != nil else { return moment.defaultEnabled }
        return defaults.bool(forKey: moment.settingKey)
    }

    public static func setEnabled(_ moment: PremiumSpokenMoment, _ on: Bool, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: moment.settingKey)
    }

    /// Words for the Zeus voice. Nil when the setting is off, or when a countdown step is not 3, 2, 1, or the start (0).
    public static func line(_ moment: PremiumSpokenMoment, countdown: Int? = nil, enabled: Bool) -> String? {
        guard enabled else { return nil }
        switch moment {
        case .recordingCountdown:
            switch countdown {
            case 3: return "Three."
            case 2: return "Two."
            case 1: return "One."
            case 0: return "Recording."
            default: return nil
            }
        case .notesReady:
            return "Notes are ready."
        case .recordingSaved:
            return "Saved."
        }
    }

    public static func spokenLine(_ moment: PremiumSpokenMoment, countdown: Int? = nil, defaults: UserDefaults = .standard) -> String? {
        line(moment, countdown: countdown, enabled: isEnabled(moment, defaults: defaults))
    }
}
