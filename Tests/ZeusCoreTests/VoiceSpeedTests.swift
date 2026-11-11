import Foundation
import Testing
@testable import ZeusCore

@Suite("Voice latency trace")
struct VoiceLatencyTraceTests {
    @Test func firstMarkWinsAndKeyUpIsZero() {
        var trace = VoiceLatencyTrace(turnID: "t1")
        #expect(trace.ms(.keyUp) == 0)
        trace.mark(.firstToken, atMs: 640)
        trace.mark(.firstToken, atMs: 900)
        trace.mark(.firstAudio, atMs: -20)
        #expect(trace.ms(.firstToken) == 640)
        #expect(trace.ms(.firstAudio) == 0)
        #expect(trace.keyUpToFirstAudioMs == 0)
    }

    @Test func logLineHasEveryStageAndNoFreeText() {
        var trace = VoiceLatencyTrace(turnID: "ab12cd34")
        trace.mark(.transcriptFinal, atMs: 310)
        trace.mark(.requestSent, atMs: 330)
        trace.mark(.firstToken, atMs: 780)
        trace.mark(.firstSentence, atMs: 1_050)
        trace.mark(.ttsRequest, atMs: 1_060)
        trace.mark(.firstAudio, atMs: 1_420)
        trace.mark(.turnEnd, atMs: 4_800)
        trace.brainEngine = "anthropic-api"
        trace.model = "claude-haiku-5-5"
        trace.ttsEngine = "elevenlabs"
        trace.voice = "elevenlabs-direct:abc"
        trace.effectPercent = 60
        trace.reason = "auto: best available, \"lowest\" latency\nsecond line"
        let line = trace.logDetail
        #expect(line.hasPrefix("turn=ab12cd34 key_up=0 transcript=310 request=330 first_token=780 first_sentence=1050 tts_request=1060 first_audio=1420 turn_end=4800 ttfa=1420"))
        #expect(line.contains("brain=anthropic-api model=claude-haiku-5-5 tts=elevenlabs voice=elevenlabs-direct:abc effect=60"))
        #expect(line.contains("reason=\"auto: best available, 'lowest' latency second line\""))
        #expect(!line.contains("\n"))
        #expect(trace.isComplete)
    }

    @Test func missingStagesPrintADash() {
        var trace = VoiceLatencyTrace(turnID: "x")
        trace.mark(.transcriptFinal, atMs: 100)
        let line = trace.logDetail
        #expect(line.contains("first_audio=-"))
        #expect(line.contains("ttfa=-"))
        #expect(line.contains("brain=- "))
        #expect(!trace.isComplete)
    }

    @Test func targetsMatchTheDocumentedBudget() {
        #expect(VoiceLatencyTargets.targetMs(apiBrain: true, cloudVoice: true) == 1_200)
        #expect(VoiceLatencyTargets.targetMs(apiBrain: true, cloudVoice: false) == 2_500)
        #expect(VoiceLatencyTargets.targetMs(apiBrain: false, cloudVoice: true) == 2_500)
        #expect(VoiceLatencyTargets.voiceLegVerdict(ms: 300).hasPrefix("fast"))
        #expect(VoiceLatencyTargets.voiceLegVerdict(ms: 900).hasPrefix("slow"))
    }
}

@Suite("Voice turn route")
struct VoiceTurnRouteTests {
    @Test func anthropicKeyWinsAndWarmsOnlyThatConnection() {
        let brain = VoiceTurnRoute.brain(VoiceTurnKeys(anthropicKey: true, openAIKey: true, claudeCLI: true))
        #expect(brain.path == "anthropic-api")
        #expect(brain.model == "claude-haiku-5-5")
        #expect(brain.warm == [.anthropicAPI])
    }

    @Test func openAIOnlyUsesTheFastOpenAIModel() {
        let brain = VoiceTurnRoute.brain(VoiceTurnKeys(openAIKey: true, claudeCLI: true))
        #expect(brain.path == "openai")
        #expect(brain.warm == [.openAIAPI])
    }

    @Test func noKeyUsesThePersistentClaudeCLIThenCodexThenNothing() {
        #expect(VoiceTurnRoute.brain(VoiceTurnKeys(claudeCLI: true, codexCLI: true)).warm == [.claudeCLI])
        #expect(VoiceTurnRoute.brain(VoiceTurnKeys(codexCLI: true)).path == "codex-cli")
        let none = VoiceTurnRoute.brain(VoiceTurnKeys())
        #expect(none.path == "none")
        #expect(none.warm.isEmpty)
    }

    @Test func targetIsTightOnlyWithAnAPIBrainAndACloudVoice() {
        #expect(VoiceTurnRoute.targetMs(VoiceTurnKeys(anthropicKey: true), cloudVoice: true) == 1_200)
        #expect(VoiceTurnRoute.targetMs(VoiceTurnKeys(claudeCLI: true), cloudVoice: true) == 2_500)
    }
}

@Suite("Persistent CLI policy")
struct PersistentCLIPolicyTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 5_000)

    @Test func reusesAWarmProcessWithTheSameFlags() {
        let slot = PersistentCLIPolicy.Slot(launchKey: "fast", turnsServed: 2, startedAt: t0, alive: true)
        #expect(PersistentCLIPolicy.action(existing: slot, wantedKey: "fast", now: t0.addingTimeInterval(60)) == .reuse)
    }

    @Test func respawnsWhenMissingDeadChangedWornOrOld() {
        let fresh = PersistentCLIPolicy.Slot(launchKey: "fast", turnsServed: 0, startedAt: t0, alive: true)
        #expect(PersistentCLIPolicy.action(existing: nil, wantedKey: "fast", now: t0) == .respawn)
        var dead = fresh
        dead.alive = false
        #expect(PersistentCLIPolicy.action(existing: dead, wantedKey: "fast", now: t0) == .respawn)
        #expect(PersistentCLIPolicy.action(existing: fresh, wantedKey: "deep", now: t0) == .respawn)
        var worn = fresh
        worn.turnsServed = PersistentCLIPolicy.maxTurns
        #expect(PersistentCLIPolicy.action(existing: worn, wantedKey: "fast", now: t0) == .respawn)
        #expect(PersistentCLIPolicy.action(existing: fresh, wantedKey: "fast",
                                           now: t0.addingTimeInterval(PersistentCLIPolicy.maxAgeSeconds + 1)) == .respawn)
    }
}

@Suite("Voice tier and first words")
struct VoiceTierAndFirstWordsTests {
    private func voice(_ name: String, quality: Int, language: String = "en-US") -> UltronSystemVoicePick.Candidate {
        UltronSystemVoicePick.Candidate(name: name, language: language, quality: quality, identifier: "id.\(name).\(quality)")
    }

    @Test func premiumBeatsEnhancedBeatsDefaultAndNeverSamantha() {
        let pool = [voice("Samantha", quality: 3), voice("Alex", quality: 1), voice("Daniel", quality: 2), voice("Evan", quality: 3)]
        #expect(UltronSystemVoicePick.pick(from: pool, languageCode: "en-US")?.name == "Evan")
        let noPremium = [voice("Samantha", quality: 3), voice("Alex", quality: 1), voice("Daniel", quality: 2)]
        #expect(UltronSystemVoicePick.pick(from: noPremium, languageCode: "en-US")?.name == "Daniel")
    }

    @Test func hintAppearsOnlyWhenNoEnhancedOrPremiumVoiceIsUsable() {
        let defaultOnly = [voice("Alex", quality: 1), voice("Samantha", quality: 3)]
        #expect(UltronSystemVoicePick.suggestsBetterVoice(from: defaultOnly, languageCode: "en-US"))
        #expect(UltronSystemVoicePick.suggestsBetterVoice(from: [], languageCode: "en-US"))
        #expect(!UltronSystemVoicePick.suggestsBetterVoice(from: [voice("Daniel", quality: 2)], languageCode: "en-US"))
        #expect(UltronSystemVoicePick.tierName(3) == "Premium")
        #expect(UltronSystemVoicePick.tierName(2) == "Enhanced")
        #expect(UltronSystemVoicePick.tierName(1) == "Default")
    }

    @Test func aLongFirstSentenceWithoutACommaSpeaksAfterTwelveWords() {
        var splitter = SentenceSplitter()
        // Tokens arrive mid-word; the twelfth word is complete only once whitespace follows it.
        var spoken = splitter.feed("The quarterly numbers look strong across every region we track and the")
        #expect(spoken.isEmpty)
        spoken = splitter.feed(" margin")
        #expect(spoken == ["The quarterly numbers look strong across every region we track and the"])
        #expect(splitter.flush() == "margin")
    }

    @Test func aShortFirstSentenceStillWaitsForItsFullStop() {
        var splitter = SentenceSplitter()
        #expect(splitter.feed("Steady and quiet ").isEmpty)
        #expect(splitter.feed("today. The desk") == ["Steady and quiet today."])
        #expect(splitter.flush() == "The desk")
    }

    @Test func onlyTheFirstChunkIsCutByWordCount() {
        var splitter = SentenceSplitter()
        let first = splitter.feed("one two three four five six seven eight nine ten eleven twelve thirteen fourteen ")
        #expect(first == ["one two three four five six seven eight nine ten eleven twelve"])
        // The rest of the sentence waits for its full stop: the word cut applies once, to the first chunk.
        let next = splitter.feed("fifteen sixteen seventeen eighteen nineteen twenty twentyone twentytwo twentythree done. ")
        #expect(next == ["thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twentyone twentytwo twentythree done."])
    }
}

@Suite("Fillers and the fast first sentence")
struct FillerTimingTests {
    @Test func noFillerWhenTheFirstTextArrivesUnderSevenHundredMilliseconds() {
        var state = TurnRaceState()
        _ = state.reduce(.released(tiers: ["anthropic-api"], deep: nil, atMs: 0))
        #expect(state.reduce(.tick(atMs: 300)).isEmpty)
        _ = state.reduce(.firstText(tier: "anthropic-api", atMs: 650))
        // Past the filler threshold, but the answer is already speaking: nothing may be added.
        let late = state.reduce(.tick(atMs: FastTier.fillerMs + 100))
        #expect(!late.contains(.speakFiller))
        #expect(!state.fillerSpoken)
        #expect(650 < FastTier.fillerMs)
    }

    @Test func aSilentStartStillGetsOneFillerAfterTheThreshold() {
        var state = TurnRaceState()
        _ = state.reduce(.released(tiers: ["claude"], deep: nil, atMs: 0))
        #expect(state.reduce(.tick(atMs: FastTier.fillerMs - 1)).isEmpty)
        #expect(state.reduce(.tick(atMs: FastTier.fillerMs)) == [.speakFiller])
        #expect(state.reduce(.tick(atMs: FastTier.fillerMs + 100)).isEmpty)
    }
}

@Suite("Voice quality, answer model pin, language and joins")
struct VoiceQualityTests {
    @Test func defaultIsFastestAndModelsAreTheNamedConstants() {
        #expect(ElevenLabsQuality.resolve(stored: nil) == .fastest)
        #expect(ElevenLabsQuality.resolve(stored: "junk") == .fastest)
        #expect(ElevenLabsQuality.resolve(stored: "studio") == .studio)
        #expect(ElevenLabsQuality.fastest.modelID == "eleven_flash_v2_5")
        #expect(ElevenLabsQuality.studio.modelID == ElevenLabsQuality.studioModel)
    }

    @Test func oneModelSpeaksTheWholeAnswer() {
        var pin = AnswerModelPin()
        #expect(pin.resolve(quality: .studio, studioUnsupported: false) == ElevenLabsQuality.studioModel)
        // Settings changed mid-answer: the pinned model still wins.
        #expect(pin.resolve(quality: .fastest, studioUnsupported: false) == ElevenLabsQuality.studioModel)
        pin.fallBackToFast()
        #expect(pin.resolve(quality: .studio, studioUnsupported: false) == "eleven_flash_v2_5")
        pin.reset()
        #expect(pin.resolve(quality: .fastest, studioUnsupported: false) == "eleven_flash_v2_5")
    }

    @Test func studioKnownUnsupportedResolvesToFast() {
        var pin = AnswerModelPin()
        #expect(pin.resolve(quality: .studio, studioUnsupported: true) == "eleven_flash_v2_5")
        #expect(AnswerModelPin.isModelRejection(status: 422))
        #expect(!AnswerModelPin.isModelRejection(status: 401))
    }

    @Test func detectsEnglishAndFrench() {
        #expect(SpokenLanguage.detect("Steady. The desk is quiet and everything is ready.") == "en")
        #expect(SpokenLanguage.detect("Tout est prêt, Tony. Le bureau est calme et tout est en ordre.") == "fr")
        #expect(SpokenLanguage.detect("ok") == nil)
    }

    private func sine(_ count: Int, phase: Double = 0.7, amplitude: Float = 0.5) -> [Float] {
        (0..<count).map { amplitude * Float(sin(phase + Double($0) * 2 * .pi * 220 / 24_000)) }
    }

    @Test func aNonZeroEdgeFadesInFourMilliseconds() {
        var samples = sine(2_400)
        let original = samples
        AudioEdge.applyFades(&samples, sampleRate: 24_000, head: true, tail: true)
        let fade = AudioEdge.fadeSamples(sampleRate: 24_000)
        #expect(fade == 96)
        #expect(samples[0] == 0)
        #expect(abs(samples[samples.count - 1]) < 0.01)
        #expect(samples[fade] == original[fade])
        #expect(samples[samples.count - 1 - fade] == original[samples.count - 1 - fade])
    }

    @Test func aBufferThatAlreadyStartsAndEndsNearZeroIsUntouched() {
        var samples = [Float](repeating: 0, count: 100) + sine(1_000, phase: 0) + [Float](repeating: 0, count: 100)
        samples[100] = 0
        let original = samples
        AudioEdge.applyFades(&samples, sampleRate: 24_000, head: true, tail: true)
        #expect(samples == original)
    }

    @Test func noFadeUnlessAskedAndShortBuffersAreClamped() {
        var samples = sine(1_000)
        let original = samples
        AudioEdge.applyFades(&samples, sampleRate: 24_000, head: false, tail: false)
        #expect(samples == original)
        var tiny: [Float] = [0.5, 0.5, 0.5]
        AudioEdge.applyFades(&tiny, sampleRate: 24_000, head: true, tail: true)
        #expect(tiny[0] == 0)
        var empty: [Float] = []
        AudioEdge.applyFades(&empty, sampleRate: 24_000, head: true, tail: true)
        #expect(empty.isEmpty)
    }

    @Test func twoSentencesJoinWithoutAJump() {
        var first = sine(4_800, phase: 0.3)
        var second = sine(4_800, phase: 1.9)
        AudioEdge.applyFades(&first, sampleRate: 24_000, head: true, tail: true)
        AudioEdge.applyFades(&second, sampleRate: 24_000, head: true, tail: true)
        let joined = first + second
        let step = abs(joined[first.count] - joined[first.count - 1])
        #expect(step < 0.01)
        // Unfaded, the same join jumps audibly (a click).
        let raw = sine(4_800, phase: 0.3) + sine(4_800, phase: 1.9)
        #expect(abs(raw[4_800] - raw[4_799]) > 0.1)
    }
}
