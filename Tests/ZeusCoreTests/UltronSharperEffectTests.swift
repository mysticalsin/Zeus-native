import Foundation
import Testing
@testable import ZeusCore

@Suite struct UltronSharperEffectTests {
    @Test func theDefaultEffectIsSeventyFivePercent() {
        #expect(UltronEffectParameters.defaultPercent == 75)
        #expect(UltronEffectParameters.percent(fromIntensity: 0.75) == 75)
        let p = UltronEffectParameters.make(percent: Double(UltronEffectParameters.defaultPercent))
        #expect(!p.isNeutral)
        #expect(abs(p.pitchCents - -387.5) < 0.01)
    }

    @Test func theMetallicLayerIsSlightlyStrongerAtEveryIntensityAndStaysIntelligible() {
        for percent in stride(from: 10.0, through: 100.0, by: 10.0) {
            let t = Float(percent / 100)
            let p = UltronEffectParameters.make(percent: percent)
            #expect(p.combWetPercent > 14 * t, "comb \(percent)")
            #expect(p.combWetPercent <= 14 * t * 1.35, "comb \(percent)")
            #expect(p.distortionWetPercent > 8 * t, "distortion \(percent)")
            #expect(p.distortionWetPercent <= 8 * t * 1.35, "distortion \(percent)")
            #expect(p.reverbWetPercent == 10 * t, "reverb \(percent)")
        }
        let full = UltronEffectParameters.make(percent: 100)
        #expect(full.combWetPercent <= 18 && full.distortionWetPercent <= 11 && full.pitchCents >= -500)
    }

    @Test func reducingTheIntensityStillRemovesTheEffectAndTheOtherAmountsAreUnchanged() {
        #expect(UltronEffectParameters.make(percent: 0).isNeutral)
        let full = UltronEffectParameters.make(percent: 100)
        #expect(full.pitchCents == -450 && full.lowShelfGainDB == 7.5 && full.highShelfGainDB == 5)
        #expect(full.combFeedbackPercent == 35 && full.outputGainDB == -2)
        #expect(UltronEffectParameters.make(percent: 60).pitchCents == -350)
    }
}
