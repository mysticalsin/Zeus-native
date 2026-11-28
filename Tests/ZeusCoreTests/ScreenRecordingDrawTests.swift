import Testing
@testable import ZeusCore

struct ScreenRecordingDrawTests {
    private func cards(_ plan: ScreenRecordingDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func thePermissionWordIsTheSecondCard() {
        let allowed = ScreenRecordingDraw.plan(word: "Allowed")
        #expect(cards(allowed) == ["Screen", "Allowed"])
        #expect(ScreenRecordingAsk.line(word: "Allowed") == "Screen recording is allowed.")
        #expect(allowed.boltCaption(at: 0) == "Screen")
        #expect(allowed.boltCaption(at: ExplainBeatSchedule.gap) == "Allowed")
        #expect(allowed.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(ScreenRecordingAsk.line(word: "Denied") == "Screen recording is denied.")
        #expect(ScreenRecordingAsk.line(word: "Not asked yet") == "Screen recording has not been asked yet.")
        #expect(cards(ScreenRecordingDraw.plan(word: "Banana")) == ["Screen", "Can't"])
        #expect(ScreenRecordingAsk.line(word: "") == "I can't read screen recording.")
    }

    @Test func theDisplayCountAndTheLicenseStayOffThisAsk() {
        #expect(ScreenRecordingAsk.matches("is screen recording on"))
        #expect(ScreenRecordingAsk.matches("Hey Zeus, can you see the screen?"))
        #expect(ScreenRecordingAsk.matches("how's screen recording"))
        #expect(!ScreenRecordingAsk.matches("how many screens"))
        #expect(!ScreenRecordingAsk.matches("which screen"))
        #expect(!ScreenRecordingAsk.matches("how's my license"))
        #expect(!ScreenRecordingAsk.matches("which voice is this"))
        #expect(!ScreenRecordingAsk.matches("where's my keyboard"))
    }
}
