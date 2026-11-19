import Foundation

/// Existing capture entry points interrupt an active explanation before starting.
/// Inert unless the opt-in explanation owns input/output; no device is opened here.
@MainActor
enum ExplanationAudioArbitration {
    static var onTakeover: (() -> Void)?
    static func yieldToNewCapture() {
        let stop = onTakeover
        onTakeover = nil
        stop?()
    }
}
