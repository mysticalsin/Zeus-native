import Darwin
import Testing
@testable import Zeus

@Suite struct UltronVoiceEffectTests {
    @Test func effectChainRendersNonSilentBuffer() {
        let input: [Float] = (0..<480).map { sin(Float($0) * 0.05) * 0.4 }
        let out = UltronVoiceEffect.process(input, intensity: 0.8)
        #expect(UltronVoiceEffect.isNonSilent(out))
    }

    @Test func disabledEffectPassesThrough() {
        let input: [Float] = [0, 0.2, -0.2, 0]
        let out = UltronVoiceEffect.process(input, intensity: 0)
        #expect(out == input)
    }
}
