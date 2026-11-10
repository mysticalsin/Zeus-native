import Foundation

/// Active provider order for one utterance (K4), skipping paused engines.
public enum VoiceTTSChain {
    public static func providers(
        chosen: VoiceTTSProvider,
        availability: VoiceProviderFallback.Availability,
        isPaused: (VoiceTTSProvider) -> Bool
    ) -> [VoiceTTSProvider] {
        VoiceProviderFallback.chain(chosen: chosen, availability: availability)
            .filter { !isPaused($0) }
    }

    public static let firstAudioTimeout: TimeInterval = 4

    public enum FailureReason: Equatable, Sendable {
        case http401
        case quota
        case timeout
        case missingModel
        case offline
        case other(String)
    }

    /// Whether a failure should move to the next provider and start a cooldown.
    public static func shouldFallback(for reason: FailureReason) -> Bool {
        switch reason {
        case .http401, .quota, .timeout, .missingModel, .offline: true
        case .other: true
        }
    }
}
