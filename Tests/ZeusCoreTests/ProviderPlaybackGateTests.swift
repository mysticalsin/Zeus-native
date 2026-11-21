import Testing
@testable import ZeusCore

@Suite("Provider playback gate")
struct ProviderPlaybackGateTests {
    @Test func theNextLineWaitsUntilProviderPlaybackEnds() {
        let gate = ProviderPlaybackGate()
        #expect(!gate.isPlaying)
        #expect(ProviderSentencePump.canDequeue(queueEmpty: false, providerPlaying: gate.isPlaying))
        let first = gate.begin()
        #expect(gate.isPlaying)
        #expect(!ProviderSentencePump.canDequeue(queueEmpty: false, providerPlaying: gate.isPlaying))
        #expect(ProviderSentencePump.holds(chainPlaying: false, systemRendering: false, providerPlaying: gate.isPlaying))
        #expect(ProviderSentencePump.isSpeaking(synthesizer: false, pump: false, chainPlaying: false, systemRendering: false, providerPlaying: gate.isPlaying))
        var spoken: [String] = []
        var queue = ["first sentence", "second sentence"]
        if ProviderSentencePump.canDequeue(queueEmpty: queue.isEmpty, providerPlaying: gate.isPlaying) {
            spoken.append(queue.removeFirst())
        }
        #expect(spoken.isEmpty)
        gate.end(first)
        #expect(!gate.isPlaying)
        #expect(ProviderSentencePump.canDequeue(queueEmpty: queue.isEmpty, providerPlaying: gate.isPlaying))
        if ProviderSentencePump.canDequeue(queueEmpty: queue.isEmpty, providerPlaying: gate.isPlaying) {
            spoken.append(queue.removeFirst())
        }
        #expect(spoken == ["first sentence"])
        #expect(!ProviderSentencePump.isSpeaking(synthesizer: false, pump: false, chainPlaying: false, systemRendering: false, providerPlaying: false))
    }

    @Test func aLateFinishDoesNotClearANewerPlayback() {
        let gate = ProviderPlaybackGate()
        let first = gate.begin()
        gate.reset()
        let second = gate.begin()
        gate.end(first)
        #expect(gate.isPlaying)
        gate.end(second)
        #expect(!gate.isPlaying)
    }

    /// ZB-027: a second clip bumps the generation, so ending the first token is ignored and
    /// ending the second only drops one level. The gate stays engaged after both clips are done.
    @Test func overlappingClipsLeaveTheGateEngaged() {
        let gate = ProviderPlaybackGate()
        let first = gate.begin()
        let second = gate.begin()
        #expect(first != second)
        #expect(gate.isPlaying)
        #expect(!ProviderSentencePump.canDequeue(queueEmpty: false, providerPlaying: gate.isPlaying))
        gate.end(first)
        #expect(gate.isPlaying)
        gate.end(second)
        #expect(!gate.isPlaying)
        #expect(ProviderSentencePump.canDequeue(queueEmpty: false, providerPlaying: gate.isPlaying))
    }
}
