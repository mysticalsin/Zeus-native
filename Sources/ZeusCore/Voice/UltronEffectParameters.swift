import Foundation

/// The Ultron post-processing chain as plain numbers, by intensity. The app maps these onto
/// AVAudioEngine units (time pitch, EQ, distortion, short comb delay, small room reverb), so the
/// numbers are testable without audio hardware. Intelligibility comes first: every wet amount is
/// small, and intensity 0 is fully neutral.
public struct UltronEffectParameters: Equatable, Sendable {
    public static let defaultPercent = 60
    public static let percentRange = 0...100

    /// Pitch shift in cents, always at or below zero (deeper).
    public var pitchCents: Float
    /// Low shelf near 140 Hz and high shelf near 4.5 kHz, in dB.
    public var lowShelfGainDB: Float
    public var highShelfGainDB: Float
    /// Short comb: a delay of about 10 ms with feedback gives the faint metallic sheen.
    public var combDelaySeconds: Double
    public var combFeedbackPercent: Float
    public var combWetPercent: Float
    /// Radio-tower style distortion at a very low mix.
    public var distortionWetPercent: Float
    /// Small room reverb.
    public var reverbWetPercent: Float
    /// Output trim so the chain does not clip.
    public var outputGainDB: Float

    public var isNeutral: Bool {
        pitchCents == 0 && lowShelfGainDB == 0 && highShelfGainDB == 0 && combWetPercent == 0
            && distortionWetPercent == 0 && reverbWetPercent == 0 && outputGainDB == 0
    }

    public static let neutral = UltronEffectParameters(
        pitchCents: 0, lowShelfGainDB: 0, highShelfGainDB: 0, combDelaySeconds: 0.010,
        combFeedbackPercent: 0, combWetPercent: 0, distortionWetPercent: 0, reverbWetPercent: 0, outputGainDB: 0)

    /// `percent` is the Settings slider, 0 to 100 (60 is the designed voice).
    public static func make(percent: Double) -> UltronEffectParameters {
        guard percent.isFinite else { return .neutral }
        let t = Float(min(max(percent, 0), 100) / 100)
        guard t > 0 else { return .neutral }
        // -3.5 semitones at 60 %, -4.5 at 100 %.
        let pitch: Float = t <= 0.6 ? -350 * (t / 0.6) : -350 - 100 * ((t - 0.6) / 0.4)
        return UltronEffectParameters(
            pitchCents: pitch,
            lowShelfGainDB: 7.5 * t,
            highShelfGainDB: 5 * t,
            combDelaySeconds: 0.010,
            combFeedbackPercent: 35 * t,
            combWetPercent: 14 * t,
            distortionWetPercent: 8 * t,
            reverbWetPercent: 10 * t,
            outputGainDB: -2 * t)
    }

    /// Intensity as stored (0 to 1) to the whole slider percent. Rounded: a Float 0.6 is 0.6000000238,
    /// and `Int(...)` of the unrounded product could read 59 for a value saved as 59.99999.
    public static func percent(fromIntensity intensity: Float) -> Double {
        intensity.isFinite ? (Double(min(max(intensity, 0), 1)) * 100).rounded() : Double(defaultPercent)
    }
}
