import Foundation

/// Lines for premium surfaces that otherwise only draw. The app speaks a returned line with the
/// existing Zeus voice. This type does not play audio, open a microphone, or capture the screen.
public enum PremiumSpokenMoment: String, CaseIterable, Sendable, Identifiable {
    case recordingCountdown
    case notesReady
    case recordingSaved

    public var id: String { rawValue }

    public var settingKey: String { "voice.speak.\(rawValue)" }

    public var settingTitle: String { "" }

    public var settingDetail: String { "" }

    public var defaultEnabled: Bool { false }

    public static func isEnabled(_ moment: PremiumSpokenMoment, defaults: UserDefaults = .standard) -> Bool {
        _ = (moment, defaults)
        return false
    }

    public static func setEnabled(_ moment: PremiumSpokenMoment, _ on: Bool, defaults: UserDefaults = .standard) {
        _ = (moment, on, defaults)
    }

    /// Words for the Zeus voice, or nil while these moments stay silent.
    public static func line(_ moment: PremiumSpokenMoment, countdown: Int? = nil, enabled: Bool) -> String? {
        _ = (moment, countdown, enabled)
        return nil
    }

    public static func spokenLine(_ moment: PremiumSpokenMoment, countdown: Int? = nil, defaults: UserDefaults = .standard) -> String? {
        line(moment, countdown: countdown, enabled: isEnabled(moment, defaults: defaults))
    }
}
