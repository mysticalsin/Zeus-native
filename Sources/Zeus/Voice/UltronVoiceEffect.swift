import Foundation
import ZeusCore

/// Post-processing for the Ultron persona on every TTS buffer (K3).
enum UltronVoiceEffect {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "voice.ultronEffect") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "voice.ultronEffect") }
    }

    static var intensity: Float {
        get { UserDefaults.standard.object(forKey: "voice.ultronEffect.intensity") as? Float ?? 0.7 }
        set { UserDefaults.standard.set(newValue, forKey: "voice.ultronEffect.intensity") }
    }

    /// Offline-friendly: scales samples so silence stays silent but speech is non-zero after processing.
    static func process(_ samples: [Float], intensity: Float = intensity, sampleRate: Double = 24_000,
                        sampleOffset: Double = 0) -> [Float] {
        guard enabled else { return samples }
        return UltronVoiceSignal.process(samples, intensity: intensity, sampleRate: sampleRate, sampleOffset: sampleOffset)
    }

    static func isNonSilent(_ samples: [Float]) -> Bool {
        samples.contains { abs($0) > 0.001 }
    }
}
