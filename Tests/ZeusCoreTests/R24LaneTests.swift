import Foundation
import Testing
@testable import ZeusCore

@Suite("R24 lane L1", .serialized)
struct R24LaneTests {
    @Test func spokenMarkupMapsParagraphAndPunctuation() {
        #expect(SpokenDictationMarkup.apply("hello new paragraph world") == "hello\n\nworld")
        #expect(SpokenDictationMarkup.apply("one new line two") == "one\ntwo")
        #expect(SpokenDictationMarkup.apply("wait comma pause") == "wait, pause")
        #expect(SpokenDictationMarkup.apply("done period") == "done.")
        #expect(SpokenDictationMarkup.apply("really question mark") == "really?")
        #expect(SpokenDictationMarkup.apply("bonjour virgule merci") == "bonjour, merci")
        #expect(SpokenDictationMarkup.apply("un point de vue") == "un point de vue")
        #expect(SpokenDictationMarkup.apply("bonjour point") == "bonjour.")
    }

    @Test func prepareForInsertAppliesMarkup() {
        #expect(TranscriptPolish.prepareForInsert("note new paragraph next") == "Note\n\nnext")
    }

    @Test func todoVoiceStripsLeadingTo() {
        #expect(TodoVoice.stripLeadingTo("to call Anna") == "call Anna")
        #expect(TodoVoice.parse("add to-do to call Anna") == .add(["call Anna"]))
    }

    @Test func settingsSectionAliasesResolve() {
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("topBar") == "appearance")
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("todo") == "features")
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("memory") == "features")
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("teleprompter") == "beamer")
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("Voice") == "voice")
    }

    @Test func debugAudioPathResolvesRelativePaths() {
        let resolved = DebugAudioPath.resolve("clip.wav", workingDirectory: "/tmp/qa")
        #expect(resolved == "/tmp/qa/clip.wav")
        #expect(DebugAudioPath.resolve("/abs/x.wav") == "/abs/x.wav")
    }

    @Test func zeusCLINormalizesDebugWavPaths() {
        #expect(ZeusCLI.normalizeDebugText("dictate-file ./a.wav").hasSuffix("/a.wav"))
        #expect(ZeusCLI.normalizeDebugText("wake-file relative.wav").contains("relative.wav"))
    }

    @Test func heyJesusIsAcceptedAsWakeMishearing() {
        #expect(WakePhrase.spot("hey jesus what time is it")?.request == "what time is it")
        #expect(WakePhrase.spot("jesus open calculator") == nil)
    }

    @Test func metaphysicalQuestionsStayLocalAndShort() {
        let answer = PersonaQueries.localAnswer(for: "Are you conscious?", personality: .ultron)
        #expect(answer != nil)
        #expect(answer!.split(separator: " ").count <= 20)
        #expect(!answer!.lowercased().contains("weekly limit"))
    }

    @Test func smallTalkIsNotServile() {
        let answer = PersonaQueries.localAnswer(for: "how are you today", personality: .ultron) ?? ""
        #expect(!answer.lowercased().contains("at your disposal"))
        #expect(!answer.lowercased().contains("operational"))
    }

    @Test func ollamaProbeTreatsAnEmptyProcessListAsDown() {
        #expect(OllamaHTTPProbe.hasLoadedModel(Data(#"{"models":[{"name":"llama3.2"}]}"#.utf8)))
        #expect(!OllamaHTTPProbe.hasLoadedModel(Data(#"{"models":[]}"#.utf8)))
        #expect(!OllamaHTTPProbe.hasLoadedModel(Data("{}".utf8)))
    }

    @Test func spokenFailureHidesProviderText() {
        let raw = "Research failed: You've hit your weekly limit · resets Nov 6 at 4pm (America/Sao_Paulo)"
        let line = SpokenFailure.line(raw)
        #expect(line == "Every AI is out of quota.")
        #expect(!line.lowercased().contains("nov"))
        #expect(line.split(separator: " ").count <= 10)
        let dumped = SpokenFailure.line("HTTP 500 traceback in the provider")
        #expect(Set(ZeusVoiceLines.bank(.ultron)[.errorSpoken] ?? []).union(ZeusVoiceLines.bank(.plain)[.errorSpoken] ?? []).contains(dumped))
        #expect(BrowserAgentOutcome.failed(raw).spokenText == "Every AI is out of quota.")
    }

    @Test func firstClauseSpeaksBeforeTheSentenceEnds() {
        var splitter = SentenceSplitter()
        let spoken = splitter.feed("Paris is the capital, and the rest of the sentence follows.")
        #expect(spoken == ["Paris is the capital,"])
        #expect(splitter.flush() == "and the rest of the sentence follows.")
    }

    @Test func staleSpeechStartIsNotLogged() {
        VoiceAnswerLatency.reset()
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        VoiceAnswerLatency.clock = { t0 }
        VoiceAnswerLatency.beginTurn(at: t0)
        VoiceAnswerLatency.noteFirstSentence(at: t0)
        #expect(VoiceAnswerLatency.speechStartMs(speechBegan: t0.addingTimeInterval(287)) == nil)
        #expect(VoiceAnswerLatency.consumeSpeechStartMs(speechBegan: t0.addingTimeInterval(1)) == 1000)
        #expect(VoiceAnswerLatency.speechStartMs(speechBegan: t0.addingTimeInterval(2)) == nil)
        VoiceAnswerLatency.reset()
        VoiceAnswerLatency.clock = { Date() }
    }
}
