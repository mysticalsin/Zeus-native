import AVFoundation
import Foundation
import Testing
import ZeusCore
@testable import Zeus

// Serialized: several AVAudioEngine graphs built at once on a host without an audio device is
// exactly the condition these tests probe; one at a time keeps a failure attributable.
@Suite(.serialized) struct UltronVoiceEffectTests {
    private func tone(seconds: Double = 0.4, amplitude: Float = 0.4) -> AVAudioPCMBuffer {
        let format = UltronAudioChain.format
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            let t = Float(index) / Float(format.sampleRate)
            channel[index] = amplitude * (sin(2 * .pi * 180 * t) + 0.5 * sin(2 * .pi * 540 * t)) / 1.5
        }
        return buffer
    }

    private func samples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    @Test func effectChainRendersNonSilentBuffer() throws {
        let input = tone()
        let out = try #require(UltronOfflineRender.render(input, parameters: .make(percent: 60)))
        let processed = samples(out)
        #expect(UltronVoiceEffect.isNonSilent(processed))
        #expect(out.frameLength >= input.frameLength)
        let original = samples(input)
        let overlap = min(original.count, processed.count)
        let difference = (0..<overlap).reduce(Float(0)) { $0 + abs(original[$1] - processed[$1]) }
        if let refusal = Self.hostRefusesChain() {
            // This host's AVFAudio refuses the chain (CI runners have no audio device): the render must
            // then be the untouched voice, never a crash or silence.
            #expect(difference < 0.001, "host refused the chain: \(refusal)")
        } else {
            #expect(difference > 1)
        }
    }

    /// Why this host's AVFAudio refuses the offline effect chain, or nil when it accepts it.
    private static func hostRefusesChain() -> String? {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let graph = UltronEffectGraph()
        engine.attach(player)
        graph.attach(to: engine)
        do {
            try engine.enableManualRenderingMode(.offline, format: UltronAudioChain.format, maximumFrameCount: 4_096)
        } catch { return "manual rendering unavailable: \(error.localizedDescription)" }
        return graph.connect(from: player, format: UltronAudioChain.format, engine: engine)
    }

    @Test func graphRefusesFormatsAvfAudioWouldRejectInsteadOfCrashing() {
        #expect(UltronEffectGraph.isConnectable(UltronAudioChain.format))
        let tooSlow = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 4_000, channels: 1, interleaved: false)!
        let integer = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: false)!
        #expect(!UltronEffectGraph.isConnectable(tooSlow))
        #expect(!UltronEffectGraph.isConnectable(integer))
        // An unconnectable format is refused before any AVAudioEngine.connect call; nothing is wired.
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let graph = UltronEffectGraph()
        engine.attach(player)
        graph.attach(to: engine)
        #expect(graph.connect(from: player, format: tooSlow, engine: engine) != nil)
    }

    @Test func disabledEffectPassesThrough() throws {
        let input = tone()
        let out = try #require(UltronOfflineRender.render(input, parameters: .neutral))
        let original = samples(input)
        let processed = samples(out)
        let drift = (0..<original.count).reduce(Float(0)) { $0 + abs(original[$1] - processed[$1]) } / Float(original.count)
        #expect(drift < 0.02)
    }

    @Test func silenceStaysSilent() throws {
        let silent = tone(amplitude: 0)
        let out = try #require(UltronOfflineRender.render(silent, parameters: .make(percent: 100)))
        #expect(!UltronVoiceEffect.isNonSilent(samples(out)))
    }

    @Test func otherFormatsAreConvertedToTheChainFormat() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22_050, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_205)!
        buffer.frameLength = 2_205
        for index in 0..<2_205 { buffer.floatChannelData![0][index] = 0.3 * sin(Float(index) * 0.1) }
        let converted = try #require(UltronAudioChain.convert(buffer))
        #expect(converted.format.sampleRate == 24_000)
        #expect(abs(Int(converted.frameLength) - 2_400) < 64)
    }

    @Test func int16StreamBecomesFloatSamples() throws {
        var bytes = Data()
        for value: Int16 in [0, 16_384, -16_384, 32_767] { withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) } }
        let buffer = try #require(UltronAudioChain.buffer(fromInt16: bytes))
        #expect(buffer.frameLength == 4)
        #expect(abs(buffer.floatChannelData![0][1] - 0.5) < 0.001)
    }


    private func fresh() -> UserDefaults {
        let name = "zeus.ultron.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func freshInstallIsUltronWithTheEffectOnAtSixtyPercent() {
        let defaults = fresh()
        #expect(ZeusPersonality.current(defaults) == .ultron)
        #expect(UltronVoiceEffect.enabled(defaults))
        #expect(UltronVoiceEffect.intensity(defaults) == 0.6)
        #expect(!UltronVoiceEffect.parameters(defaults).isNeutral)
    }

    @Test func anExplicitOwnerChoiceIsKept() {
        let defaults = fresh()
        defaults.set(false, forKey: UltronVoiceEffect.enabledKey)
        defaults.set(Float(0.3), forKey: UltronVoiceEffect.intensityKey)
        #expect(!UltronVoiceEffect.enabled(defaults))
        #expect(UltronVoiceEffect.parameters(defaults).isNeutral)
        defaults.set(true, forKey: UltronVoiceEffect.enabledKey)
        #expect(UltronVoiceEffect.intensity(defaults) == 0.3)
    }

    @Test func firstSpokenLineWithNoKeysUsesTheDeepestMacVoiceNeverSamantha() {
        // No key, no Kokoro: the chain is the Mac voice alone, run through the effect.
        #expect(UltronEngineRouter.chain(choice: .auto, availability: UltronEngineAvailability()).map(\.engine) == [.system])
        for voice in AVSpeechSynthesisVoice.speechVoices() {
            let pick = Speaker.bestVoice(for: voice.language)
            #expect(pick?.name != "Samantha")
        }
    }
}
