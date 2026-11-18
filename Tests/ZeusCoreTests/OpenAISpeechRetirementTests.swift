import Foundation
import Testing
@testable import ZeusCore

@Suite("OpenAI speech retirement (shutdown 2027-01-06)")
struct OpenAISpeechRetirementTests {
    private let before = Date(timeIntervalSince1970: 1_799_193_599)
    private let at = Date(timeIntervalSince1970: 1_799_193_600)
    private let after = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func retirementDateIsJanuarySixth2027Utc() {
        #expect(OpenAISpeechRetirement.shutdownDate == at)
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: OpenAISpeechRetirement.shutdownDate)
        #expect([parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second] == [2027, 1, 6, 0, 0, 0])
    }

    @Test func deprecatedSpeechModelsAreRetiredFromTheShutdownInstant() {
        let models = ["tts-1", "tts-1-hd", "gpt-4o-mini-tts", "gpt-4o-mini-tts-2025-03-20", "gpt-4o-mini-tts-2025-12-15"]
        for model in models {
            #expect(!OpenAISpeechRetirement.isRetired(model: model, at: before), "\(model) still works before")
            #expect(OpenAISpeechRetirement.isRetired(model: model, at: at), "\(model) retired at the instant")
            #expect(OpenAISpeechRetirement.isRetired(model: model, at: after), "\(model) retired after")
        }
    }

    @Test func onlyTheFiveListedIdsAreRetiredNotPrefixes() {
        for model in ["gpt-4o-mini-tts-2026-06-01", "tts-1-hd-2030-01-01", "tts-12", "gpt-4o-mini-tts2"] {
            #expect(!OpenAISpeechRetirement.isRetired(model: model, at: after), "\(model) is not on the list")
            #expect(OpenAISpeechRetirement.settingsNote(model: model, at: before) == nil)
        }
    }

    @Test func onlyTheOpenAIHostIsRetiredACustomBaseURLKeepsWorking() {
        let ours = [nil, "", "https://api.openai.com/v1", "HTTPS://API.OPENAI.COM/v1"]
        for base in ours {
            #expect(OpenAISpeechRetirement.isRetired(model: "tts-1", baseURL: base, at: after), "\(base ?? "default")")
            #expect(OpenAISpeechRetirement.settingsNote(model: "tts-1", baseURL: base, at: before) == OpenAISpeechRetirement.upcomingNote)
        }
        for base in ["http://localhost:8000/v1", "https://tts.example.com/v1", "not a url"] {
            #expect(!OpenAISpeechRetirement.isRetired(model: "tts-1", baseURL: base, at: after), "\(base)")
            #expect(OpenAISpeechRetirement.settingsNote(model: "tts-1", baseURL: base, at: before) == nil)
            #expect(OpenAISpeechRetirement.settingsNote(model: "tts-1", baseURL: base, at: after) == nil)
            #expect(OpenAIVoiceCatalog.voices(forModel: "tts-1", baseURL: base, at: after).count == 9)
        }
        #expect(OpenAIVoiceCatalog.voices(forModel: "tts-1", baseURL: nil, at: after).isEmpty)
    }

    @Test func aSavedOpenAIChoiceAfterShutdownShowsTheFallbackEngine() {
        let line = OpenAISpeechRetirement.endedChoiceLine(choice: .fixed(.openAI), retired: true, effective: "Kokoro")
        #expect(line == "OpenAI voices ended. Zeus uses Kokoro.")
        #expect(OpenAISpeechRetirement.endedChoiceLine(choice: .fixed(.openAI), retired: false, effective: "Kokoro") == nil)
        #expect(OpenAISpeechRetirement.endedChoiceLine(choice: .auto, retired: true, effective: "Kokoro") == nil)
        #expect(OpenAISpeechRetirement.endedChoiceLine(choice: .fixed(.elevenLabs), retired: true, effective: "Kokoro") == nil)
        #expect(!(line ?? "").contains("\u{2014}"))
    }

    @Test func otherModelsAreNeverRetiredByThisPolicy() {
        for model in ["kokoro", "gpt-realtime-2.1-mini", "my-local-tts", ""] {
            #expect(!OpenAISpeechRetirement.isRetired(model: model, at: after))
        }
    }

    @Test func routerNeverSelectsOpenAIAfterShutdownAndFallsThroughLikeNoKey() {
        let retired = UltronEngineAvailability(elevenLabsConfigured: true, openAIConfigured: true, kokoroReady: true, openAIRetired: true)
        let noKey = UltronEngineAvailability(elevenLabsConfigured: true, openAIConfigured: false, kokoroReady: true)
        let expected: [UltronEngine] = [.elevenLabs, .kokoro, .system]
        #expect(UltronEngineRouter.chain(choice: .auto, availability: retired).map(\.engine) == expected)
        #expect(UltronEngineRouter.chain(choice: .auto, availability: noKey).map(\.engine) == expected)
        // A saved OpenAI choice is kept but not used: the chain is the one the no-key owner gets.
        #expect(UltronEngineRouter.chain(choice: .fixed(.openAI), availability: retired).map(\.engine) == expected)
        #expect(UltronEngineRouter.chain(choice: .fixed(.openAI), availability: noKey).map(\.engine) == expected)
        #expect(retired.skipReason(.openAI) == "OpenAI voices ended January 6, 2027")
    }

    @Test func routerWithOnlyOpenAIAfterShutdownSpeaksWithTheMacVoice() {
        let only = UltronEngineAvailability(openAIConfigured: true, openAIRetired: true)
        #expect(UltronEngineRouter.chain(choice: .auto, availability: only).map(\.engine) == [.system])
        #expect(UltronEngineRouter.chain(choice: .fixed(.openAI), availability: only).map(\.engine) == [.system])
    }

    @Test func routerBeforeShutdownIsUnchanged() {
        let live = UltronEngineAvailability(elevenLabsConfigured: true, openAIConfigured: true, kokoroReady: true,
                                            openAIRetired: OpenAISpeechRetirement.isRetired(model: "gpt-4o-mini-tts", at: before))
        #expect(UltronEngineRouter.chain(choice: .auto, availability: live).map(\.engine) == [.elevenLabs, .openAI, .kokoro, .system])
        #expect(UltronEngineRouter.chain(choice: .fixed(.openAI), availability: live).map(\.engine) == [.openAI, .elevenLabs, .kokoro, .system])
    }

    @Test func catalogHidesOpenAIVoicesAfterShutdownOnly() {
        #expect(OpenAIVoiceCatalog.voices(forModel: "gpt-4o-mini-tts", at: before).count == 13)
        #expect(OpenAIVoiceCatalog.voices(forModel: "gpt-4o-mini-tts", at: before) == OpenAIVoiceCatalog.voices(forModel: "gpt-4o-mini-tts"))
        #expect(OpenAIVoiceCatalog.voices(forModel: "tts-1", at: before).count == 9)
        #expect(OpenAIVoiceCatalog.voices(forModel: "gpt-4o-mini-tts", at: after).isEmpty)
        #expect(OpenAIVoiceCatalog.voices(forModel: "tts-1-hd", at: at).isEmpty)
    }

    @Test func settingsNoteIsOnePlainSentencePairBeforeAndAfter() {
        let ends = "OpenAI ends these voices on January 6, 2027. Zeus will switch to your next voice then."
        #expect(OpenAISpeechRetirement.settingsNote(model: "gpt-4o-mini-tts", at: before) == ends)
        #expect(OpenAISpeechRetirement.settingsNote(model: "gpt-4o-mini-tts", at: after) == "Ended January 6, 2027")
        #expect(OpenAISpeechRetirement.settingsNote(model: "my-local-tts", at: before) == nil)
        #expect(OpenAISpeechRetirement.settingsNote(model: "my-local-tts", at: after) == nil)
        #expect(!ends.contains("\u{2014}") && !ends.contains("\u{2013}"))
    }
}
