import Foundation
import Testing
@testable import ZeusCore

/// Marks become due from the audio start the caller reports for each sentence.
@Suite struct SpeechMarkScheduleTests {
    @Test func sentenceZeroStartsAtAudioZeroSoItsMarksAreDueAndSentenceOnesAreNot() {
        var schedule = SpeechMarkSchedule(marks: [
            .init(id: "ring", sentenceIndex: 0),
            .init(id: "underline", sentenceIndex: 0),
            .init(id: "arrow", sentenceIndex: 1),
        ])
        let opened = schedule.apply(sentenceIndex: 0, audioStartSeconds: 0)
        #expect(opened.map(\.id) == ["ring", "underline"])
        #expect(opened.allSatisfy { $0.sentenceIndex == 0 && $0.audioStartSeconds == 0 })
        let atZero = schedule.due(at: 0)
        #expect(atZero.map(\.sentenceIndex) == [0, 0])
        #expect(!atZero.contains { $0.sentenceIndex == 1 })
    }

    @Test func aLateCueIsAppliedOnceAndNotReplayed() {
        var schedule = SpeechMarkSchedule(marks: [
            .init(id: "ring", sentenceIndex: 0),
            .init(id: "label", sentenceIndex: 1),
        ])
        _ = schedule.apply(sentenceIndex: 0, audioStartSeconds: 0)
        let late = schedule.apply(sentenceIndex: 1, audioStartSeconds: 2.4)
        #expect(late.map(\.id) == ["label"])
        #expect(late.map(\.audioStartSeconds) == [2.4])
        #expect(schedule.apply(sentenceIndex: 1, audioStartSeconds: 2.4).isEmpty)
        #expect(schedule.apply(sentenceIndex: 1, audioStartSeconds: 2.5).isEmpty)
        #expect(schedule.due(at: 2.4).map(\.id) == ["ring", "label"])
    }

    @Test func cancelReturnsNoFurtherMarks() {
        var schedule = SpeechMarkSchedule(marks: [
            .init(id: "ring", sentenceIndex: 0),
            .init(id: "label", sentenceIndex: 1),
        ])
        _ = schedule.apply(sentenceIndex: 0, audioStartSeconds: 0)
        schedule.cancel()
        #expect(schedule.apply(sentenceIndex: 1, audioStartSeconds: 1.1).isEmpty)
        #expect(schedule.due(at: 0).isEmpty)
        #expect(schedule.due(at: 3).isEmpty)
    }

    @Test func aMarkWithAFutureTimestampIsNotShownBeforeItsAudio() {
        var schedule = SpeechMarkSchedule(marks: [
            .init(id: "now", sentenceIndex: 0, dueSeconds: 0),
            .init(id: "later", sentenceIndex: 0, dueSeconds: 2),
        ])
        let shown = schedule.apply(sentenceIndex: 0, audioStartSeconds: 0)
        #expect(shown.map(\.id) == ["now"])
        #expect(schedule.due(at: 1).map(\.id) == ["now"])
        #expect(schedule.due(at: 2).map(\.id) == ["now", "later"])
    }

    @Test func aMarkMissingItsStartExpiresWithoutBecomingDue() {
        var schedule = SpeechMarkSchedule(marks: [
            .init(id: "lost", sentenceIndex: 3),
        ])
        #expect(schedule.due(at: 0).isEmpty)
        #expect(schedule.pendingIDs(at: 0) == ["lost"])
        let bound = SpeechMarkSchedule.missingStartExpirySeconds
        #expect(schedule.pendingIDs(at: bound).isEmpty)
        #expect(schedule.due(at: bound).isEmpty)
        #expect(schedule.pendingIDs(at: bound - 0.001) == ["lost"])
    }

    @Test func bargeInCallsCancel() {
        var schedule = SpeechMarkSchedule(marks: [
            .init(id: "ring", sentenceIndex: 0, dueSeconds: 0),
            .init(id: "later", sentenceIndex: 0, dueSeconds: 2),
        ])
        _ = schedule.apply(sentenceIndex: 0, audioStartSeconds: 0)
        schedule.bargeIn()
        #expect(schedule.due(at: 5).isEmpty)
        #expect(schedule.apply(sentenceIndex: 1, audioStartSeconds: 1).isEmpty)
    }

    @Test func theWordEstimateIsOnlyAFallbackWhenRealTimingIsMissing() {
        let schedule = SpeechMarkSchedule(marks: [
            .init(id: "guessed", sentenceIndex: 0, wordIndex: 2),
            .init(id: "real", sentenceIndex: 1, dueSeconds: 1),
        ])
        #expect(schedule.due(at: 0.2).isEmpty)
        let guessed = schedule.due(at: 2 * SpeechMarkSchedule.estimatedSecondsPerWord)
        #expect(guessed.map(\.id) == ["guessed"])
        #expect(guessed.allSatisfy { $0.estimated })
        #expect(guessed.allSatisfy { $0.timingDisclosure == SpeechMarkSchedule.estimatedTimingDisclosure })
        let atOne = schedule.due(at: 1)
        let real = atOne.first { $0.id == "real" }
        #expect(real?.estimated == false && real?.timingDisclosure.isEmpty == true)
        #expect(atOne.first { $0.id == "guessed" }?.estimated == true)
    }
}
