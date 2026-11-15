import Foundation

// What the per-app sound card draws and says, kept apart from the view so it can be tested: the labels and spoken
// names of the ten bands, how a band slider maps a gain to a position and back, and the points of the response
// curve. Pure and `Sendable`. The curve comes from the filter maths, never from audio.

/// One vertical band slider's rules: a gain from -12 to +12 dB in steps of 0.5, with its labels.
public enum EqualiserBandControl {
    /// Where the slider draws its tick marks, in decibels.
    public static let ticks: [Double] = [-12, -6, 0, 6, 12]

    /// The short label under a band: "31.5", "63", "1k", "16k". Empty for an index outside the ten bands.
    public static func label(at index: Int) -> String {
        guard let hertz = hertz(at: index) else { return "" }
        return hertz >= 1000 ? "\(compact(hertz / 1000))k" : compact(hertz)
    }

    /// What VoiceOver says for the band: "125 hertz band", "1 kilohertz band". Empty outside the ten bands.
    public static func spokenName(at index: Int) -> String {
        guard let hertz = hertz(at: index) else { return "" }
        return hertz >= 1000 ? "\(compact(hertz / 1000)) kilohertz band" : "\(compact(hertz)) hertz band"
    }

    /// Inside the range and on a half-decibel step. Not a number becomes 0.
    public static func snapped(_ gain: Double) -> Double {
        let clamped = EqualiserGain.clamp(gain)
        return EqualiserGain.clamp((clamped / EqualiserGain.step).rounded() * EqualiserGain.step)
    }

    /// 0 at the bottom of the track (-12 dB), 0.5 at the centre (0 dB) and 1 at the top (+12 dB).
    public static func fraction(for gain: Double) -> Double {
        let span = EqualiserGain.range.upperBound - EqualiserGain.range.lowerBound
        return (EqualiserGain.clamp(gain) - EqualiserGain.range.lowerBound) / span
    }

    /// The snapped gain at a position along the track, 0 at the bottom and 1 at the top. A position outside the track
    /// gives the nearest end. Not a number gives 0 dB.
    public static func gain(atFraction fraction: Double) -> Double {
        guard !fraction.isNaN else { return 0 }
        let position = min(max(fraction, 0), 1)
        let span = EqualiserGain.range.upperBound - EqualiserGain.range.lowerBound
        return snapped(EqualiserGain.range.lowerBound + position * span)
    }

    /// One keyboard or VoiceOver adjustment: a number of half-decibel steps, stopping at the ends.
    public static func adjusted(_ gain: Double, steps: Int) -> Double {
        snapped(snapped(gain) + Double(steps) * EqualiserGain.step)
    }

    private static func hertz(at index: Int) -> Double? {
        EqualiserBandLayout.tenBandFrequencies.indices.contains(index) ? EqualiserBandLayout.tenBandFrequencies[index] : nil
    }

    /// 31.5 stays "31.5"; 125 is "125", never "125.0".
    private static func compact(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// The response curve the card draws under the band sliders.
public enum EqualiserCurve {
    public struct Point: Sendable, Equatable {
        public let frequency: Double
        public let decibels: Double

        public init(frequency: Double, decibels: Double) {
            self.frequency = frequency
            self.decibels = decibels
        }
    }

    public static let pointCount = 64
    public static let lowFrequency = 20.0
    public static let highFrequency = 20_000.0
    /// The vertical span the card draws, the same as one band's range.
    public static let displayRange = EqualiserGain.range

    /// `pointCount` points, log-spaced from 20 Hz to 20 kHz, each the sum in decibels of the ten band sections at that
    /// frequency. Gains are clamped, and missing ones count as 0.
    public static func points(gainsDB: [Double], sampleRate: Double = 48_000) -> [Point] {
        let bands = EqualiserBand.standard
        let gains = (0..<bands.count).map { gainsDB.indices.contains($0) ? EqualiserGain.clamp(gainsDB[$0]) : 0 }
        let sections = zip(bands, gains).map { band, gain in
            BiquadDesign.coefficients(
                kind: band.kind, frequency: band.frequency, gainDB: gain, q: band.q, sampleRate: sampleRate)
        }
        let ratio = highFrequency / lowFrequency
        return (0..<pointCount).map { index in
            let frequency = lowFrequency * pow(ratio, Double(index) / Double(pointCount - 1))
            let decibels = sections.reduce(0.0) {
                $0 + BiquadDesign.magnitudeDB($1, frequency: frequency, sampleRate: sampleRate)
            }
            return Point(frequency: frequency, decibels: decibels)
        }
    }
}
