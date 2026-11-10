import Foundation
import Testing
@testable import ZeusCore

@Suite("QA21 latency clock", .serialized)
struct QA21LatencyTests {
    @Test func speechStartMsUsesInjectedClock() {
        VoiceAnswerLatency.reset()
        let t0 = Date(timeIntervalSinceReferenceDate: 100)
        VoiceAnswerLatency.clock = { t0.addingTimeInterval(2) }
        VoiceAnswerLatency.beginTurn(at: t0)
        VoiceAnswerLatency.noteFirstSentence(at: t0.addingTimeInterval(0.5))
        let ms = VoiceAnswerLatency.speechStartMs(speechBegan: t0.addingTimeInterval(1.2))
        #expect(ms == 700)
        VoiceAnswerLatency.reset()
        VoiceAnswerLatency.clock = { Date() }
    }

    @Test func subSecondSpeechStartRoundsToWholeMilliseconds() {
        VoiceAnswerLatency.reset()
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        VoiceAnswerLatency.clock = { t0 }
        VoiceAnswerLatency.beginTurn(at: t0)
        VoiceAnswerLatency.noteFirstSentence(at: t0)
        #expect(VoiceAnswerLatency.consumeSpeechStartMs(speechBegan: t0.addingTimeInterval(0.4)) == 400)
        VoiceAnswerLatency.reset()
        VoiceAnswerLatency.clock = { Date() }
    }

    @Test func firstSentenceIsRecordedOnce() {
        VoiceAnswerLatency.reset()
        let t0 = Date(timeIntervalSinceReferenceDate: 200)
        VoiceAnswerLatency.clock = { t0 }
        VoiceAnswerLatency.beginTurn(at: t0)
        VoiceAnswerLatency.noteFirstSentence(at: t0.addingTimeInterval(0.1))
        VoiceAnswerLatency.noteFirstSentence(at: t0.addingTimeInterval(0.9))
        let ms = VoiceAnswerLatency.speechStartMs(speechBegan: t0.addingTimeInterval(0.5))
        #expect(ms == 400)
        VoiceAnswerLatency.reset()
        VoiceAnswerLatency.clock = { Date() }
    }
}

@Suite("QA21 default shortcuts")
struct QA21ShortcutTests {
    private func defaults() -> UserDefaults {
        let suite = "zeus.qa21.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func shippedTalkAndDictationKeysDoNotOverlap() {
        let d = defaults()
        let talk = ShortcutStore.loadTalk(d)
        let dictation = ShortcutStore.loadDictation(d)
        #expect(talk == .optionCommand)
        #expect(dictation == .rightCommand)
        #expect(ShortcutConflicts.warningsForShippedDefaults(talk: talk, dictation: dictation).isEmpty)
    }
}
