import Foundation
import Testing
@testable import ZeusCore

@Suite("Speech engine catalog")
struct SpeechEngineCatalogTests {
    @Test func everyEngineHasATitleDescriptionAndGroup() {
        for kind in TranscriptionEngineKind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(kind.detail.count > 20, "\(kind) needs an honest one-line description")
            #expect(!kind.detail.contains("\n"))
            #expect(TranscriptionEngineKind.engines(in: kind.group).contains(kind))
        }
        let titles = TranscriptionEngineKind.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
    }

    @Test func groupsSplitLocalFromCloud() {
        #expect(TranscriptionEngineKind.engines(in: .cloud) == [.elevenLabs, .openAI])
        #expect(TranscriptionEngineKind.engines(in: .onThisMac) == [.parakeet, .parakeetUltra, .whisperKit, .whisper, .appleAnalyzer, .apple, .fasterWhisper])
        #expect(TranscriptionEngineKind.Group.allCases.map(\.rawValue) == ["On this Mac", "Cloud"])
    }

    @Test func cloudEnginesSayAudioLeavesAndUseExistingKeySlots() {
        for kind in TranscriptionEngineKind.engines(in: .cloud) {
            #expect(kind.detail.contains("Audio leaves this Mac"))
            #expect(!kind.needsDownload)
        }
        #expect(TranscriptionEngineKind.elevenLabs.keyAccount == "elevenlabs.api-key")
        #expect(TranscriptionEngineKind.openAI.keyAccount == "assistant.key.openAI")
        #expect(TranscriptionEngineKind.engines(in: .onThisMac).allSatisfy { $0.keyAccount == nil })
    }

    @Test func fasterWhisperIsLabelledSlowerOnMac() {
        #expect(TranscriptionEngineKind.fasterWhisper.detail.contains("Slower on Mac"))
    }

    @Test func persistedEngineNamesStillDecode() {
        for raw in ["parakeet", "whisper", "fasterWhisper", "apple"] {
            #expect(TranscriptionEngineKind(rawValue: raw) != nil)
        }
    }

    @Test func cloudIsNeverAnAutomaticFallback() {
        #expect(!EngineSelection.fallbackOrder.contains { $0.isCloud })
        #expect(EngineSelection.fallbackOrder.last == .apple)
        // A cloud engine is used when chosen and ready…
        #expect(EngineSelection.resolve(preferred: .openAI, availability: [.openAI: .ready, .apple: .ready]) == .openAI)
        // …but a missing key drops to a local engine, never to the other cloud one.
        #expect(EngineSelection.resolve(preferred: .openAI, availability: [.openAI: .needsKey, .elevenLabs: .ready, .apple: .ready]) == .apple)
    }

    // MARK: Status mapping

    @Test func statusLinesMatchThePicker() {
        let ready = EngineStatusMapping.line(for: .parakeet, availability: .ready, selected: false)
        #expect(ready.label == "Ready" && ready.ok && ready.action == .use && ready.actionTitle == "Use")

        let inUse = EngineStatusMapping.line(for: .parakeet, availability: .ready, selected: true)
        #expect(inUse.action == .inUse && inUse.actionTitle == nil)

        let download = EngineStatusMapping.line(for: .parakeet, availability: .notDownloaded, selected: false)
        #expect(download.label == "Download 480 MB" && download.action == .download && download.actionTitle == "Download")

        let whisper = EngineStatusMapping.line(for: .whisper, availability: .notDownloaded, selected: false, megabytes: 574)
        #expect(whisper.label == "Download 574 MB")

        let faster = EngineStatusMapping.line(for: .fasterWhisper, availability: .notDownloaded, selected: false)
        #expect(faster.actionTitle == "Set up")

        let key = EngineStatusMapping.line(for: .elevenLabs, availability: .needsKey, selected: false)
        #expect(key.label == "Needs key" && key.action == .addKey && key.actionTitle == "Add key")

        let old = EngineStatusMapping.line(for: .appleAnalyzer, availability: .needsNewerMacOS, selected: false)
        #expect(old.label == "Not available on this macOS" && old.action == .none && old.actionTitle == nil)

        let downloading = EngineStatusMapping.line(for: .parakeetUltra, availability: .downloading(0.416), selected: false)
        #expect(downloading.label == "Downloading 42 %" && downloading.action == .none)

        let missing = EngineStatusMapping.line(for: .whisperKit, availability: .unavailable("Needs WhisperKit."), selected: false)
        #expect(missing.reason == "Needs WhisperKit." && missing.action == .none)
    }

    @Test func recommendationBadges() {
        #expect(EngineRecommendation.badge(for: .parakeet, whisperKitUsable: false)?.contains("fastest") == true)
        #expect(EngineRecommendation.badge(for: .whisperKit, whisperKitUsable: true) != nil)
        #expect(EngineRecommendation.badge(for: .whisper, whisperKitUsable: true) == nil)
        #expect(EngineRecommendation.badge(for: .whisper, whisperKitUsable: false) != nil)
        #expect(EngineRecommendation.badge(for: .whisperKit, whisperKitUsable: false) == nil)
        #expect(EngineRecommendation.badge(for: .openAI, whisperKitUsable: true) == nil)
        #expect(EngineRecommendation.isUsable(.notDownloaded))
        #expect(!EngineRecommendation.isUsable(.unavailable("x")))
        #expect(!EngineRecommendation.isUsable(nil))
    }

    // MARK: Vocabulary

    @Test func termsPutTheUsersWordsFirstThenTheBuiltInNames() {
        let terms = DictationVocabularyPrompt.terms(Vocabulary(words: ["Walteur", "zeus"]))
        #expect(terms.first == "Walteur")
        #expect(terms.contains("Claude") && terms.contains("Codex") && terms.contains("Murmure") && !terms.contains("Laya") && terms.contains("Jev"))
        // "zeus" from the person counts as Zeus: no duplicate.
        #expect(terms.filter { $0.lowercased() == "zeus" }.count == 1)
        #expect(terms.contains("Soul"))
        #expect(DictationVocabularyPrompt.terms(Vocabulary(words: (0..<300).map { "w\($0)" })).count == 100)
    }

    @Test func mergedVocabularyRestoresNameCasingButNotOrdinaryWords() {
        let merged = DictationVocabularyPrompt.merged(Vocabulary())
        #expect(merged.apply(to: "ask claude and codex in zeus") == "ask Claude and Codex in Zeus")
        #expect(merged.apply(to: "body and soul") == "body and soul")
    }

    @Test func whisperPromptIsAPunctuatedSentenceWithinBudget() {
        #expect(DictationVocabularyPrompt.whisperPrompt(terms: []) == "")
        #expect(DictationVocabularyPrompt.whisperPrompt(terms: ["Zeus", "Laya", "Jev"]) == "Names: Zeus, Laya, Jev.")
        let long = DictationVocabularyPrompt.whisperPrompt(terms: (0..<200).map { "Name\($0)" }, maxCharacters: 120)
        #expect(long.count <= 120)
        #expect(long.hasSuffix("."))
    }

    @Test func cloudKeywordsDropWhatTheApisReject() {
        let keywords = DictationVocabularyPrompt.cloudKeywords(["Zeus", "a<b", "line\nbreak", "  Laya ", "zeus", String(repeating: "x", count: 60)])
        #expect(keywords == ["Zeus", "Laya"])
    }

    @Test func polishTidiesSpacingAndCapitalises() {
        #expect(TranscriptPolish.tidy("  hello   there , zeus .  ") == "Hello there, zeus.")
        #expect(TranscriptPolish.tidy("Already fine.") == "Already fine.")
        #expect(TranscriptPolish.tidy("") == "")
        #expect(TranscriptPolish.tidy("élan vital") == "Élan vital")
    }

    // MARK: Self-correction (P0 item D, QA7)

    @Test func selfCorrectSwapsNumbersAroundNoAndNoWait() {
        #expect(TranscriptPolish.selfCorrect("meet at 3 no 4 pm") == "meet at 4 pm")
        #expect(TranscriptPolish.selfCorrect("meet at 3 no wait 4 pm") == "meet at 4 pm")
        #expect(TranscriptPolish.selfCorrect("call her at 5 non 6") == "call her at 6")
        #expect(TranscriptPolish.selfCorrect("appelle-la à 5 non attends 6") == "appelle-la à 6")
    }

    // Regression (QA round 9): a real recognizer writes small numbers as words and adds a comma
    // around the correction pause, not bare digits with only spaces -- this is the exact text
    // Parakeet produced from `say`-ing PLAN-QA7's own example sentence through the mic, and the
    // digit-only, no-comma version of the pattern silently never matched it.
    @Test func selfCorrectSwapsSpelledOutNumbersWithCommasAroundTheCue() {
        #expect(TranscriptPolish.selfCorrect("Meet me at three, no, four pm.") == "Meet me at four pm.")
        #expect(TranscriptPolish.selfCorrect("meet at three, no wait, four pm") == "meet at four pm")
        #expect(TranscriptPolish.selfCorrect("call her at twenty-two, non, thirty-one") == "call her at thirty-one")
    }

    @Test func selfCorrectDropsTheWordBeforeSorryAndSplicesWhatFollows() {
        #expect(TranscriptPolish.selfCorrect("send it to Paul, sorry, to Marc") == "send it to Marc")
    }

    @Test func selfCorrectMakeThatReplacesTheStaleValue() {
        #expect(TranscriptPolish.selfCorrect("set a reminder for 3pm, make that 4pm") == "set a reminder for 4pm")
    }

    @Test func selfCorrectActuallyAndIMeanAndFrenchEquivalents() {
        #expect(TranscriptPolish.selfCorrect("email Dana, actually email Sam") == "email Sam")
        #expect(TranscriptPolish.selfCorrect("call the office, I mean the clinic") == "call the clinic")
        #expect(TranscriptPolish.selfCorrect("appelle Jean, en fait appelle Marie") == "appelle Marie")
        #expect(TranscriptPolish.selfCorrect("appelle Jean, pardon, appelle Marie") == "appelle Marie")
    }

    @Test func selfCorrectScratchThatDropsTheClauseBeforeIt() {
        #expect(TranscriptPolish.selfCorrect("call Paul now, scratch that, call Marc instead") == "call Marc instead")
        #expect(TranscriptPolish.selfCorrect("Call Paul now. Scratch that.") == "")
        #expect(TranscriptPolish.selfCorrect("appelle Paul, efface ça, appelle Marc") == "appelle Marc")
    }

    @Test func prepareForInsertHandlesO19ScratchAndFillers() {
        let spoken = "um, send it Tuesday, scratch that, Wednesday"
        #expect(TranscriptPolish.prepareForInsert(spoken) == "Send it Wednesday")
    }

    @Test func selfCorrectHasNoFalsePositives() {
        for text in ["I have no idea", "actually good", "I have no idea what to do", "no, that's fine",
                     "I'm sorry for the trouble", "make that reservation for two"] {
            #expect(TranscriptPolish.selfCorrect(text) == text, "\(text)")
        }
    }

    @Test func selfCorrectLeavesOrdinaryTextAlone() {
        let text = "add milk and eggs to the shopping list"
        #expect(TranscriptPolish.selfCorrect(text) == text)
    }

    // MARK: Fallback

    @Test func fallbackKeepsTheChosenEnginesWords() {
        #expect(DictationFallback.decide(chosen: .parakeet, outcome: .text(" hi there "), live: "hi their") == .keep("hi there"))
    }

    @Test func fallbackUsesAppleLiveWordsWithAToastWhenTheEngineFails() {
        let decision = DictationFallback.decide(chosen: .elevenLabs, outcome: .failed("ElevenLabs could not be reached."), live: "hello")
        #expect(decision == .useLive("hello", toast: "ElevenLabs Scribe v2 failed. Apple on-device took over."))
    }

    @Test func fallbackRetranscribesWhenAppleHadNoLiveWords() {
        #expect(DictationFallback.decide(chosen: .whisperKit, outcome: .failed("x"), live: "  ")
            == .retranscribe(toast: DictationFallback.toast(for: .whisperKit)))
    }

    @Test func fallbackQuietlyUsesAppleWhenTheEngineHeardNothing() {
        #expect(DictationFallback.decide(chosen: .parakeet, outcome: .text(""), live: "hello") == .useLive("hello", toast: nil))
        #expect(DictationFallback.decide(chosen: .parakeet, outcome: .text(""), live: "") == .nothing)
    }

    // MARK: WhisperKit CLI

    @Test func whisperKitCLIArguments() {
        let withModel = WhisperKitCLI.arguments(audioPath: "/t/a.wav", modelPath: "/m", language: "fr", prompt: "Names: Zeus.")
        #expect(withModel == ["transcribe", "--audio-path", "/t/a.wav", "--model-path", "/m", "--language", "fr",
                              "--prompt", "Names: Zeus.", "--skip-special-tokens", "--without-timestamps"])
        let fetch = WhisperKitCLI.arguments(audioPath: "/t/a.wav", modelPath: nil, language: nil, prompt: "")
        #expect(fetch.contains("--model") && fetch.contains(WhisperKitCLI.model) && !fetch.contains("--prompt"))
        #expect(!fetch.contains("--language"))
    }

    @Test func whisperKitCLIOutputIsCleaned() {
        #expect(WhisperKitCLI.clean("Loading models\nTranscription:\n\n<|startoftranscript|> Hello Zeus. [BLANK_AUDIO]\n") == "Hello Zeus.")
        #expect(WhisperKitCLI.clean(" Bonjour à tous.\n") == "Bonjour à tous.")
    }
}
