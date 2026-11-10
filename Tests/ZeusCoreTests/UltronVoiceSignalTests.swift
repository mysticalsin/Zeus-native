import Foundation
import Testing
@testable import ZeusCore

@Suite struct UltronVoiceSignalTests {
    @Test func pausesStaySilentAtEveryIntensity() {
        let silence = [Float](repeating: 0, count: 4_800)
        for intensity: Float in [0, 0.7, 1, 10] {
            #expect(UltronVoiceSignal.process(silence, intensity: intensity, sampleRate: 24_000) == silence)
        }
    }

    @Test func effectPreservesTimingAndDoesNotAddSoundOutsideSpeech() {
        let speech: [Float] = (0..<480).map { sin(Float($0) * 0.05) * 0.4 }
        let input = [Float](repeating: 0, count: 80) + speech + [Float](repeating: 0, count: 80)
        let output = UltronVoiceSignal.process(input, intensity: 0.8, sampleRate: 24_000)
        #expect(output.count == input.count)
        #expect(output.prefix(80).allSatisfy { $0 == 0 })
        #expect(output.suffix(80).allSatisfy { $0 == 0 })
        #expect(output.contains { abs($0) > 0.1 })
        #expect(output != input)
    }

    @Test func textureFrequencyIsIndependentOfProviderSampleRate() {
        let low = UltronVoiceSignal.process([Float](repeating: 0.5, count: 480), intensity: 1, sampleRate: 24_000)
        let high = UltronVoiceSignal.process([Float](repeating: 0.5, count: 960), intensity: 1, sampleRate: 48_000)
        for index in low.indices { #expect(abs(low[index] - high[index * 2]) < 0.00001) }
    }

    @Test func outputIsBoundedAndNonFiniteInputDoesNotPropagate() {
        let output = UltronVoiceSignal.process([0, 2, -2, .infinity, .nan], intensity: 100, sampleRate: 48_000)
        #expect(output.allSatisfy { $0.isFinite && abs($0) <= 1 })
        #expect(output[3] == 0 && output[4] == 0)
    }

    @Test func streamingChunksMatchOneContinuousBuffer() {
        let input: [Float] = (0..<8_127).map { sin(Float($0) * 0.037) * 0.4 }
        for rate in [24_000.0, 48_000.0] {
            let whole = UltronVoiceSignal.process(input, intensity: 0.8, sampleRate: rate)
            var streamed: [Float] = []
            var start = 0
            for count in [113, 2_048, 1, 3_777, 2_188] {
                let end = start + count
                streamed += UltronVoiceSignal.process(Array(input[start..<end]), intensity: 0.8,
                                                       sampleRate: rate, sampleOffset: Double(start))
                start = end
            }
            #expect(streamed == whole)
        }
    }

    @Test func disabledOrInvalidConfigurationPassesThrough() {
        let input: [Float] = [0, 0.2, -0.2, 0]
        for intensity: Float in [0, -1, .nan] {
            #expect(UltronVoiceSignal.process(input, intensity: intensity, sampleRate: 24_000) == input)
        }
        #expect(UltronVoiceSignal.process(input, intensity: 1, sampleRate: 0) == input)
        #expect(UltronVoiceSignal.process(input, intensity: 1, sampleRate: 24_000, sampleOffset: .nan) == input)
        #expect(UltronVoiceSignal.process(input, intensity: 1, sampleRate: 24_000, sampleOffset: -1) == input)
    }
}
