import Foundation

/// What the Settings status row shows for a machine state: one word, one SF Symbol, the countdown text while away,
/// and the sentence VoiceOver reads. Status is never color alone: the symbol and the word carry it.
public struct FacePresenceStatus: Equatable, Sendable {
    /// "Watching", "Away 1:42" and so on.
    public let word: String
    public let symbol: String
    /// "1:42" while away, nil otherwise. The row draws it in tabular numerals.
    public let countdown: String?
    /// "Face presence status: Away, 1 minute 42 seconds left".
    public let accessibilityText: String

    public static func make(state: FacePresenceMachine.State, lockAfter: Double, uptime: Double) -> FacePresenceStatus {
        switch state {
        case .away(let since):
            let remaining = max(0, lockAfter - (uptime - since))
            let clock = countdownText(seconds: remaining)
            return FacePresenceStatus(word: "Away \(clock)", symbol: "person.crop.circle.badge.clock", countdown: clock,
                                      accessibilityText: "Face presence status: Away, \(spokenDuration(seconds: remaining)) left")
        case .off: return plain("Off", "person.crop.circle")
        case .needsCameraConsent: return plain("Needs camera", "video.slash")
        case .enrolling: return plain("Enrolling", "person.crop.circle.badge.plus")
        case .watching: return plain("Watching", "eye")
        case .present: return plain("Present", "person.crop.circle.badge.checkmark")
        case .paused(.lockedByZeus): return plain("Locked", "lock")
        case .paused: return plain("Paused", "pause.circle")
        case .unavailable: return plain("Unavailable", "exclamationmark.triangle")
        }
    }

    /// Minutes and seconds, "1:42". A part of a second counts as the second still to go, so 0:00 shows only once
    /// the lock is due. Never negative.
    public static func countdownText(seconds: Double) -> String {
        let whole = wholeSeconds(seconds)
        return "\(whole / 60):" + (whole % 60 < 10 ? "0" : "") + "\(whole % 60)"
    }

    /// The same time in words for VoiceOver: "1 minute 42 seconds", "5 minutes", "0 seconds".
    public static func spokenDuration(seconds: Double) -> String {
        let whole = wholeSeconds(seconds)
        var parts: [String] = []
        if whole / 60 > 0 { parts.append("\(whole / 60) minute" + (whole / 60 == 1 ? "" : "s")) }
        if whole % 60 > 0 { parts.append("\(whole % 60) second" + (whole % 60 == 1 ? "" : "s")) }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }

    private static func wholeSeconds(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds, 86_400).rounded(.up))
    }

    private static func plain(_ word: String, _ symbol: String) -> FacePresenceStatus {
        FacePresenceStatus(word: word, symbol: symbol, countdown: nil, accessibilityText: "Face presence status: \(word)")
    }
}
