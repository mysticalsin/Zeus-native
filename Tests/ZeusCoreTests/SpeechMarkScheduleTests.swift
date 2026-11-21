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
}
