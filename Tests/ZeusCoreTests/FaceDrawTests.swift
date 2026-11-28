import Testing
@testable import ZeusCore

struct FaceDrawTests {
    private func cards(_ plan: FaceDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func thePageWordIsTheSecondCard() {
        let watching = FaceDraw.plan(word: "Watching")
        #expect(cards(watching) == ["Face", "Watching"])
        #expect(FaceAsk.line(word: "Watching") == "Face presence is watching.")
        #expect(watching.boltCaption(at: 0) == "Face")
        #expect(watching.boltCaption(at: ExplainBeatSchedule.gap) == "Watching")
        #expect(watching.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(FaceDraw.plan(word: "Away 1:42")) == ["Face", "Away 1:42"])
        #expect(FaceAsk.line(word: "Away 1:42") == "You are away, with 1:42 left.")
        #expect(FaceAsk.line(word: "Present") == "You are present.")
        #expect(FaceAsk.line(word: "Needs camera") == "Face presence needs the camera.")
        #expect(cards(FaceDraw.plan(word: "Away 1:9")) == ["Face", "Can't"])
        #expect(cards(FaceDraw.plan(word: "Ana")) == ["Face", "Can't"])
        #expect(FaceAsk.line(word: "") == "I can't read face presence.")
    }

    @Test func heyZeusAndTheHeatStayOffThisAsk() {
        #expect(FaceAsk.matches("how's face presence"))
        #expect(FaceAsk.matches("Hey Zeus, is face presence on?"))
        #expect(FaceAsk.matches("is my face present"))
        #expect(!FaceAsk.matches("is hey zeus on"))
        #expect(!FaceAsk.matches("how's the heat"))
        #expect(!FaceAsk.matches("is dictation on"))
        #expect(!FaceAsk.matches("how many chats"))
        #expect(!FaceAsk.matches("what's my battery"))
    }
}
