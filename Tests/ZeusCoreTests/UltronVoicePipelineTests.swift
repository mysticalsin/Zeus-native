import Foundation
import Testing
@testable import ZeusCore

@Suite("Ultron effect parameters")
struct UltronEffectParametersTests {
    @Test func zeroIntensityIsNeutral() {
        #expect(UltronEffectParameters.make(percent: 0).isNeutral)
        #expect(UltronEffectParameters.make(percent: .nan).isNeutral)
    }

    @Test func defaultIsSixtyPercentAtAboutThreeAndAHalfSemitonesDown() {
        let p = UltronEffectParameters.make(percent: Double(UltronEffectParameters.defaultPercent))
        #expect(UltronEffectParameters.defaultPercent == 60)
        #expect(p.pitchCents == -350)
        #expect(!p.isNeutral)
    }

    @Test func everyAmountGrowsWithIntensityAndStaysTasteful() {
        var previous = UltronEffectParameters.make(percent: 0)
        for percent in stride(from: 10.0, through: 100.0, by: 10.0) {
            let p = UltronEffectParameters.make(percent: percent)
            #expect(p.pitchCents <= previous.pitchCents)
            #expect(p.lowShelfGainDB >= previous.lowShelfGainDB)
            #expect(p.highShelfGainDB >= previous.highShelfGainDB)
            #expect(p.combWetPercent >= previous.combWetPercent)
            #expect(p.reverbWetPercent >= previous.reverbWetPercent)
            // Intelligibility first: the wet effects stay small, the comb stays near 10 ms.
            #expect(p.distortionWetPercent <= 10)
            #expect(p.combWetPercent <= 15)
            #expect(p.reverbWetPercent <= 12)
            #expect(p.pitchCents >= -500)
            #expect((0.008...0.012).contains(p.combDelaySeconds))
            previous = p
        }
    }

    @Test func outOfRangeIntensityIsClamped() {
        #expect(UltronEffectParameters.make(percent: 250) == UltronEffectParameters.make(percent: 100))
        #expect(UltronEffectParameters.make(percent: -5).isNeutral)
        #expect(UltronEffectParameters.percent(fromIntensity: 0.6) == 60)
    }
}

@Suite("Ultron engine routing")
struct UltronEngineRouterTests {
    typealias A = UltronEngineAvailability

    private func engines(_ choice: UltronEngineChoice, _ a: A, observed: [UltronEngine: Int] = [:]) -> [UltronEngine] {
        UltronEngineRouter.chain(choice: choice, availability: a, observedFirstAudioMs: observed).map(\.engine)
    }

    @Test func nothingConfiguredSpeaksWithTheMacVoiceAndSaysWhy() {
        let chain = UltronEngineRouter.chain(choice: .auto, availability: A())
        #expect(chain.map(\.engine) == [.system])
        #expect(chain[0].reason.contains("no cloud or local voice is ready"))
    }

    @Test func availabilityMatrixInAutoMode() {
        #expect(engines(.auto, A(elevenLabsConfigured: true)) == [.elevenLabs, .system])
        #expect(engines(.auto, A(openAIConfigured: true)) == [.openAI, .system])
        #expect(engines(.auto, A(kokoroReady: true)) == [.kokoro, .system])
        #expect(engines(.auto, A(elevenLabsConfigured: true, openAIConfigured: true, kokoroReady: true)) == [.elevenLabs, .openAI, .kokoro, .system])
        #expect(engines(.auto, A(elevenLabsConfigured: true, elevenLabsPaused: true, openAIConfigured: true)) == [.openAI, .system])
        #expect(engines(.auto, A(elevenLabsConfigured: true, elevenLabsPaused: true, openAIConfigured: true, openAIPaused: true, kokoroReady: true)) == [.kokoro, .system])
    }

    @Test func systemIsAlwaysLastAndAlwaysPresent() {
        for e in [true, false] { for o in [true, false] { for k in [true, false] { for c in [true, false] {
            let a = A(elevenLabsConfigured: e, openAIConfigured: o, kokoroReady: k, chatterboxReady: c)
            for choice in [UltronEngineChoice.auto] + UltronEngine.allCases.map({ UltronEngineChoice.fixed($0) }) {
                let chain = engines(choice, a)
                #expect(chain.last == .system)
                #expect(chain.filter { $0 == .system }.count == 1)
                #expect(Set(chain).count == chain.count)
            }
        } } } }
    }

    @Test func chatterboxCloneIsNeverPickedAutomatically() {
        #expect(!engines(.auto, A(kokoroReady: true, chatterboxReady: true)).contains(.chatterbox))
        #expect(engines(.fixed(.chatterbox), A(chatterboxReady: true)).first == .chatterbox)
    }

    @Test func explicitChoiceLeadsWhenUsableAndExplainsWhenNot() {
        let ready = A(elevenLabsConfigured: true, kokoroReady: true)
        let chosen = UltronEngineRouter.chain(choice: .fixed(.kokoro), availability: ready)
        #expect(chosen.first?.engine == .kokoro)
        #expect(chosen.first?.reason == "chosen in Settings")
        let missing = UltronEngineRouter.chain(choice: .fixed(.openAI), availability: ready)
        #expect(missing.first?.engine == .elevenLabs)
        #expect(missing.first?.reason.contains("OpenAI voice chosen but no OpenAI key") == true)
    }

    @Test func aSlowEngineDropsBehindAFasterOne() {
        let both = A(elevenLabsConfigured: true, kokoroReady: true)
        #expect(engines(.auto, both, observed: [.elevenLabs: 3_400, .kokoro: 900]) == [.kokoro, .elevenLabs, .system])
        #expect(engines(.auto, both, observed: [.elevenLabs: 400]) == [.elevenLabs, .kokoro, .system])
    }

    @Test func everyDecisionHasAReasonAndNoKeyMaterial() {
        let all = A(elevenLabsConfigured: true, openAIConfigured: true, kokoroReady: true)
        for d in UltronEngineRouter.chain(choice: .auto, availability: all) {
            #expect(!d.reason.isEmpty)
            #expect(!d.reason.lowercased().contains("sk-"))
        }
    }

    @Test func legacyPlanDelegatesToTheRouter() {
        #expect(UltronVoicePlan.preferred(kokoroReady: true, elevenLabsKeyValid: true) == .elevenLabs)
        #expect(UltronVoicePlan.preferred(kokoroReady: true, elevenLabsKeyValid: false) == .kokoro)
        #expect(UltronVoicePlan.preferred(kokoroReady: false, elevenLabsKeyValid: false) == .system)
    }
}

@Suite("Ultron system voice")
struct UltronSystemVoicePickTests {
    typealias C = UltronSystemVoicePick.Candidate
    private func c(_ name: String, _ lang: String = "en-US", _ q: Int = 1) -> C { C(name: name, language: lang, quality: q, identifier: "id.\(name)") }

    @Test func neverSamantha() {
        #expect(UltronSystemVoicePick.pick(from: [c("Samantha")], languageCode: "en-US") == nil)
        let picked = UltronSystemVoicePick.pick(from: [c("Samantha", "en-US", 3), c("Daniel", "en-GB")], languageCode: "en-US")
        #expect(picked?.name == "Daniel")
    }

    @Test func noFemaleOrNoveltyVoiceIsEverPicked() {
        for name in ["Samantha", "Karen", "Moira", "Tessa", "Fiona", "Zarvox", "Bubbles", "Whisper", "Albert", "Flo"] {
            #expect(UltronSystemVoicePick.pick(from: [c(name, "en-US", 3)], languageCode: "en-US") == nil, "\(name)")
        }
    }

    @Test func aPremiumDeepMaleVoiceBeatsACompactOne() {
        let picked = UltronSystemVoicePick.pick(from: [c("Daniel", "en-GB", 1), c("Evan", "en-US", 3), c("Samantha", "en-US", 3)], languageCode: "en-US")
        #expect(picked?.name == "Evan")
    }

    @Test func prefersTheDeepestNamedVoiceAtEqualQualityAndMatchingLocale() {
        let picked = UltronSystemVoicePick.pick(from: [c("Rishi", "en-IN"), c("Daniel", "en-GB"), c("Tom", "en-US")], languageCode: "en-US")
        #expect(picked?.name == "Tom")
    }

    @Test func pacingIsMeasuredAndPitchIsLowered() {
        #expect(UltronSystemVoicePick.rate(defaultRate: 0.5) < 0.5)
        #expect(UltronSystemVoicePick.pitchMultiplier < 1)
    }
}

@Suite("Sentence streaming")
struct SentenceStreamingTests {
    @Test func chunksStreamedDeltasIntoCompleteSentences() {
        var chunker = SentenceChunker()
        var out: [String] = []
        for delta in ["Good eve", "ning, Tony. The desk is q", "uiet. Shall we", " begin? Yes"] { out += chunker.feed(delta) }
        #expect(out == ["Good evening, Tony.", "The desk is quiet.", "Shall we begin?"])
        #expect(chunker.flush() == "Yes")
        #expect(chunker.flush() == nil)
    }

    @Test func decimalsAndAbbreviationsDoNotEndASentence() {
        var chunker = SentenceChunker()
        let out = chunker.feed("It is 3.5 percent. Dr. Lee agrees. Done.")
        #expect(out == ["It is 3.5 percent.", "Dr. Lee agrees."])
        #expect(chunker.flush() == "Done.")
    }

    @Test func receiptPassesOnlyWhenTheMacVoiceSpokeAndWasNotSamantha() throws {
        let row = VoiceSelfTestRow(engine: "system", available: true, reason: "spoke", spoke: true, firstAudioMs: 120, effectPercent: 60)
        let good = VoiceSelfTestReceipt(created: "2026-11-11T00:00:00Z", line: "Hello.", systemVoice: "Evan enhanced", rows: [row])
        #expect(good.passed)
        #expect(!VoiceSelfTestReceipt(created: "", line: "", systemVoice: "Samantha default", rows: [row]).passed)
        let decoded = try JSONDecoder().decode(VoiceSelfTestReceipt.self, from: good.json())
        #expect(decoded == good)
    }
}

@Suite("Ultron cloud voice")
struct UltronCloudVoiceTests {
    private let base = URL(string: "https://api.openai.com/v1")!

    @Test func instructionsAreSentOnlyToModelsThatAcceptThem() throws {
        let tuned = OpenAITTSRequest.Config(baseURL: base, model: UltronCloudVoice.openAIModel, voice: UltronCloudVoice.openAIVoice,
                                            apiKey: "k", instructions: UltronCloudVoice.openAIInstructions, responseFormat: "pcm")
        let body = OpenAITTSRequest.body(text: "Hi.", config: tuned)
        #expect(body["instructions"] as? String == UltronCloudVoice.openAIInstructions)
        #expect(body["response_format"] as? String == "pcm")
        #expect(body["voice"] as? String == "onyx")
        var old = tuned
        old.model = "tts-1"
        #expect(OpenAITTSRequest.body(text: "Hi.", config: old)["instructions"] == nil)
    }

    @Test func defaultOpenAIRequestStaysAWavFile() {
        let plain = OpenAITTSRequest.Config(baseURL: base, model: "tts-1", voice: "alloy", apiKey: "k")
        #expect(OpenAITTSRequest.body(text: "Hi.", config: plain)["response_format"] as? String == "wav")
    }

    @Test func voiceDescriptionNamesQualitiesNotAPersonOrAFilm() {
        let text = UltronCloudVoice.openAIInstructions.lowercased()
        #expect(text.contains("baritone"))
        #expect(!text.contains("spader") && !text.contains("avengers") && !text.contains("marvel"))
    }
}

@Suite("Ultron persona")
struct UltronPersonaTests {
    @Test func freshDefaultsAreUltron() {
        let name = "zeus.persona.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(ZeusPersonality.current(defaults) == .ultron)
        defaults.set("plain", forKey: ZeusPersonality.defaultsKey)
        #expect(ZeusPersonality.current(defaults) == .plain)
    }

    @Test func spokenReplyNeverExceedsThreeSentences() {
        let long = "One. Two. Three. Four. Five."
        for transcript in ["explain how it works", "tell me more", "walk me through it", "hello", "thanks", "remind me at six"] {
            let out = PersonaReplyClamp.clamp(long, transcript: transcript, personality: .ultron)
            #expect(out.filter { ".!?".contains($0) }.count <= PersonaReplyClamp.voiceMaxSentences)
        }
        #expect(PersonaReplyClamp.voiceMaxSentences == 3)
    }

    @Test func fillerAndErrorLinesAreInCharacterAndPlain() {
        for personality in ZeusPersonality.allCases {
            for situation in [ZeusVoiceLines.Situation.thinking, .errorSpoken] {
                for line in ZeusVoiceLines.bank(personality)[situation] ?? [] {
                    #expect(!PersonaCompliance.violatesFeelingClaim(line), "\(line)")
                    #expect(!PersonaCompliance.hasOminousHedge(line), "\(line)")
                    #expect(!line.contains("\u{2014}"), "\(line)")
                    #expect(line.split(separator: " ").count <= 10, "\(line)")
                }
            }
        }
        #expect(ZeusVoiceLines.bank(.ultron)[.thinking]?.contains("A moment.") == true)
        #expect(ZeusVoiceLines.bank(.ultron)[.thinking]?.contains("Let me look.") == true)
        #expect(!AckLines.filler(personality: .ultron).isEmpty)
    }

    @Test func aTechnicalErrorBecomesAnInCharacterLine() {
        let spoken = SpokenFailure.line("brain: codex failed; claude failed; HTTP 401 from the provider")
        let bank = Set(ZeusVoiceLines.bank(.ultron)[.errorSpoken] ?? []).union(ZeusVoiceLines.bank(.plain)[.errorSpoken] ?? [])
        #expect(bank.contains(spoken))
        #expect(!spoken.lowercased().contains("http"))
    }
}
