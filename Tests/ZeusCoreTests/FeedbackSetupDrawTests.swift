import Testing
@testable import ZeusCore

struct FeedbackSetupDrawTests {
    private func cards(_ plan: FeedbackSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallPlaysCuesAtSixty() {
        let usual = FeedbackSetupDraw.plan(feedback: "On", volume: "60")
        #expect(cards(usual) == ["Feedback", "Feedback: On", "Volume: 60%"])
        #expect(FeedbackSetupAsk.line(feedback: "On", volume: "60") == "Sound feedback is on, and the cue volume is 60 percent.")
        #expect(usual.boltCaption(at: 0) == "Feedback")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Volume: 60%")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(FeedbackSetupAsk.line(feedback: "Off", volume: "0") == "Sound feedback is off, and the cue volume is 0 percent.")
        #expect(cards(FeedbackSetupDraw.plan(feedback: "On", volume: "100")) == ["Feedback", "Feedback: On", "Volume: 100%"])
        #expect(cards(FeedbackSetupDraw.plan(feedback: "On", volume: "101")) == ["Feedback", "Can't"])
        #expect(FeedbackSetupAsk.line(feedback: "On", volume: "060") == "I can't read the sound feedback.")
    }

    @Test func theMacVolumeStaysOffThisAsk() {
        #expect(FeedbackSetupAsk.matches("how is sound feedback set"))
        #expect(FeedbackSetupAsk.matches("Hey Zeus, is sound feedback on?"))
        #expect(FeedbackSetupAsk.matches("what is the cue volume"))
        #expect(!FeedbackSetupAsk.matches("what is the volume"))
        #expect(!FeedbackSetupAsk.matches("how loud"))
        #expect(!FeedbackSetupAsk.matches("what are the cue sounds"))
        #expect(!FeedbackSetupAsk.matches("how are system notifications set"))
    }
}
