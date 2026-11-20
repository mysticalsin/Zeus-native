import Foundation
import Testing
@testable import ZeusCore

@Suite struct LocalVoiceBackendContractTests {
    private func tone(_ value: Float) -> [Float] {
        Array(repeating: value, count: VoiceFrame.sampleCount)
    }

    @Test func startReturnsFrameZeroOf3200Samples() async throws {
        let first = tone(0.25)
        let backend = try FakeDuplexVoiceBackend(frames: [first, tone(0.5)])
        let frame = try await backend.start()
        #expect(frame.samples.count == VoiceFrame.sampleCount)
        #expect(frame.samples == first)
    }

    @Test func aWrongSizeFrameThrows() async throws {
        let backend = try FakeDuplexVoiceBackend(frames: [tone(0.25), tone(0.5)])
        _ = try await backend.start()
        await #expect(throws: DuplexVoiceError.wrongFrameSize(count: 3)) {
            try await backend.push(userFrame: [0, 0, 0])
        }
    }

    @Test func aPushBeforeStartThrows() async throws {
        let backend = try FakeDuplexVoiceBackend(frames: [tone(0.25)])
        await #expect(throws: DuplexVoiceError.pushBeforeStart) {
            try await backend.push(userFrame: tone(0.1))
        }
    }

    @Test func aPushAfterCloseThrows() async throws {
        let backend = try FakeDuplexVoiceBackend(frames: [tone(0.25), tone(0.5)])
        _ = try await backend.start()
        await backend.close()
        await #expect(throws: DuplexVoiceError.pushAfterClose) {
            try await backend.push(userFrame: tone(0.1))
        }
    }

    @Test func flagsDefaultToOff() throws {
        let flags = LocalVoiceFlags()
        #expect(flags.conversationMode == false)
        #expect(flags.pocketTTS == false)

        let fresh = try JSONDecoder().decode(PersistedVoiceSettings.self, from: Data("{}".utf8))
        #expect(fresh.resolvedEngine(kokoroReady: true, elevenLabsKeyValid: true) == .elevenLabs)
        #expect(fresh.resolvedProvider(kokoroReady: true, elevenLabsKeyValid: true) == .elevenLabs)
        #expect(fresh.resolvedEngineAuto())

        let saved = Data("""
        {"voice.engine":"kokoro","voice.engine.userSelected":true,"voice.ttsProvider":"kokoro","voice.engine.auto":false}
        """.utf8)
        let kept = try JSONDecoder().decode(PersistedVoiceSettings.self, from: saved)
        #expect(kept.resolvedEngine(kokoroReady: false, elevenLabsKeyValid: false) == .kokoro)
        #expect(kept.resolvedProvider(kokoroReady: false, elevenLabsKeyValid: true) == .kokoro)
        #expect(kept.resolvedEngineAuto() == false)

        let withFlagsOff = Data("""
        {"voice.engine":"system","voice.engine.userSelected":true,"conversationMode":false,"pocketTTS":false}
        """.utf8)
        let stillSystem = try JSONDecoder().decode(PersistedVoiceSettings.self, from: withFlagsOff)
        #expect(stillSystem.resolvedEngine(kokoroReady: true, elevenLabsKeyValid: true) == .system)
    }
}
