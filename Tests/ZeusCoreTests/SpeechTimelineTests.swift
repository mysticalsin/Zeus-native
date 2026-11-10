import Testing
@testable import ZeusCore

@Suite struct SpeechTimelineTests {
    private var oneSecond: [SpeechWord] {
        (0..<6).map { index in
            let start = Double(index) * (1.0 / 6.0)
            return SpeechWord(text: "w\(index)", start: start, end: start + 0.12)
        }
    }

    @Test func threeStepsShareAOneSecondUtteranceWithoutStartingTogether() {
        let timeline = SpeechDrawingTimeline.schedule(words: oneSecond, stepCount: 3)
        #expect(timeline.cues.count == 3)
        #expect(timeline.cues[0].start == 0)
        #expect(timeline.cues[2].end <= 1)
        let starts = timeline.cues.map(\.start)
        #expect(starts[0] < starts[1])
        #expect(starts[1] < starts[2])
        #expect(timeline.step(at: 0) == 0)
        #expect(timeline.step(at: 0.9) == 2)
        #expect(timeline.step(at: -0.1) == nil)
    }

    @Test func realWordTimesReplaceTheEstimate() {
        let estimate = SpeechDrawingTimeline.estimate(text: "Explain the Pythagorean theorem and draw it now please", stepCount: 3)
        #expect(estimate.usedEstimate)
        #expect(estimate.cues.last!.end > 1)
        let committed = estimate.committed(words: oneSecond, stepCount: 3)
        #expect(!committed.usedEstimate)
        #expect(committed.cues.last!.end <= 1)
        #expect(committed.step(at: 0.5) != nil)
    }

    @Test func aClickOrKeyCancelsTheRest() {
        var timeline = SpeechDrawingTimeline.schedule(words: oneSecond, stepCount: 3)
        timeline.interrupt(reason: "click")
        #expect(timeline.cancelled)
        #expect(timeline.cancelReason == "click")
        #expect(timeline.step(at: 0.5) == nil)
    }

    @Test func lateWordTimingsCannotReviveACancelledDrawing() {
        var timeline = SpeechDrawingTimeline.estimate(text: "draw three marks", stepCount: 3)
        timeline.interrupt(reason: "user input")
        let late = timeline.committed(words: oneSecond, stepCount: 3)
        #expect(late.cancelled)
        #expect(late.cancelReason == "user input")
        #expect(late.step(at: 0.9) == nil)
    }

    @Test func dictateTextReportDrawsTheIdentityWithoutDollarSigns() {
        let report = PresentTimeline.report(text: "Explain the Pythagorean theorem and draw it")
        #expect(report.contains("source=text"))
        #expect(report.contains("math=a²+b²=c²"))
        #expect(report.contains("mathHasDollar=false"))
        #expect(report.contains("step0.start=0.000"))
        #expect(report.contains("step2.start="))
    }
}
