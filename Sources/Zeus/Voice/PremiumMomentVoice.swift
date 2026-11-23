import Foundation
import ZeusCore

/// Hands one premium line to the live Zeus voice. The app installs `play` with the talk speaker.
/// Nothing here starts a new engine, opens a microphone, or captures audio.
@MainActor
enum PremiumMomentVoice {
    static var play: (@MainActor (String) -> Void)?

    static func speak(_ moment: PremiumSpokenMoment, countdown: Int? = nil, defaults: UserDefaults = .standard) {
        guard let line = PremiumSpokenMoment.spokenLine(moment, countdown: countdown, defaults: defaults) else { return }
        play?(line)
    }
}
