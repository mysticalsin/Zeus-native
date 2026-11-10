import Foundation

/// A subtle metallic texture for already-synthesized speech. This is amplitude modulation,
/// not pitch shifting. Multiplication keeps pauses silent instead of adding a free-running tone.
public enum UltronVoiceSignal {
    public static func process(_ samples: [Float], intensity: Float, sampleRate: Double, sampleOffset: Double = 0) -> [Float] {
        guard intensity.isFinite, intensity > 0.01, sampleRate.isFinite, sampleRate > 0,
              sampleOffset.isFinite, sampleOffset >= 0 else { return samples }
        let amount = min(intensity, 1)
        let depth = 0.08 * amount
        let gain = 0.92 + 0.08 * amount
        // Frequency is in hertz so 24 kHz and 48 kHz providers get the same texture.
        let phaseStep = 2 * Double.pi * 580 / sampleRate
        guard phaseStep.isFinite else { return samples }
        return samples.enumerated().map { index, sample in
            guard sample.isFinite else { return 0 }
            // A stream carries its absolute sample offset between chunks. Add as Double so a
            // long-running stream never overflows an integer frame counter.
            let phase = (sampleOffset + Double(index)) * phaseStep
            guard phase.isFinite else { return max(-1, min(1, sample)) }
            let modulation = 1 + depth * Float(sin(phase))
            return max(-1, min(1, sample * modulation * gain))
        }
    }
}
