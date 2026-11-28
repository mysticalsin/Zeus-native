import Testing
@testable import ZeusCore

struct CueSoundsDrawTests {
    private func cards(_ plan: CueSoundsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theFourCuesFollowSounds() {
        let cues = CueSoundsDraw.plan(start: "Classic", requests: "Notebook", answer: "Futuristic 1", done: "Success")
        #expect(cards(cues) == ["Sounds", "Start: Classic", "Requests: Notebook", "Answer: Futuristic 1", "Done: Success"])
        #expect(CueSoundsAsk.line(start: "Classic", requests: "Notebook", answer: "Futuristic 1", done: "Success") == "Run start is Classic, requests are Notebook, your answer is Futuristic 1, and completion is Success.")
        #expect(cues.boltCaption(at: 0) == "Sounds")
        #expect(cues.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Done: Success")
        #expect(cues.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(CueSoundsAsk.line(start: "Off", requests: "Off", answer: "Off", done: "Off") == "Run start is Off, requests are Off, your answer is Off, and completion is Off.")
        #expect(cards(CueSoundsDraw.plan(start: "Glass", requests: "Classic", answer: "Futuristic 1", done: "Success")) == ["Sounds", "Can't"])
        #expect(CueSoundsAsk.line(start: "", requests: "Classic", answer: "Futuristic 1", done: "Success") == "I can't read the cue sounds.")
    }

    @Test func theVolumeLevelAndTheOutputStayOffThisAsk() {
        #expect(CueSoundsAsk.matches("what are the cue sounds"))
        #expect(CueSoundsAsk.matches("Hey Zeus, how's the cues?"))
        #expect(CueSoundsAsk.matches("cue sounds"))
        #expect(!CueSoundsAsk.matches("what's the volume"))
        #expect(!CueSoundsAsk.matches("where is the sound going"))
        #expect(!CueSoundsAsk.matches("which tabs are on"))
        #expect(!CueSoundsAsk.matches("which notch lights"))
    }
}
