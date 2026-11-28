import Testing
@testable import ZeusCore

struct ClipboardCountDrawTests {
    private func cards(_ plan: ClipboardCountDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func oneClipDrawsTheKindThenTheCount() {
        let plan = ClipboardCountDraw.plan(count: 1, kind: "text")
        #expect(plan.map(cards) == ["Clips", "Text", "1 clip"])
        #expect(ClipboardCountAsk.line(count: 1, kind: "text") == "You have 1 text clip.")
        #expect(ClipboardCountAsk.line(count: 1, kind: "secret password 4242") == "You have 1 clip.")
        #expect(plan?.boltCaption(at: 0) == "Clips")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Text")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "1 clip")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(ClipboardCountDraw.plan(count: 0, kind: "text") == nil)
        let secret = ClipboardCountAsk.line(count: 1, kind: "secret password 4242") ?? ""
        #expect(!secret.contains("4242"))
        #expect(!secret.contains("password"))
    }

    @Test func severalClipsDrawTheCountAndTheShelfIsNotThisAsk() {
        let plan = ClipboardCountDraw.plan(count: 5, kind: "image")
        #expect(plan.map(cards) == ["Clips", "5 clips", "Image"])
        #expect(ClipboardCountAsk.line(count: 5, kind: "image") == "You have 5 clips. The newest is image.")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "5 clips")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Image")
        #expect(cards(ClipboardCountDraw.empty()) == ["Clips", "None"])
        #expect(ClipboardCountAsk.empty == "The clipboard is empty.")
        #expect(ClipboardCountAsk.matches("what's on my clipboard"))
        #expect(ClipboardCountAsk.matches("Hey Zeus, how many clips?"))
        #expect(ClipboardCountAsk.matches("my clipboard"))
        #expect(!ClipboardCountAsk.matches("read my clipboard"))
        #expect(!ClipboardCountAsk.matches("what's on my shelf"))
        #expect(!ClipboardCountAsk.matches("how many to-dos"))
        #expect(!ClipboardCountAsk.matches("what's my week"))
    }
}
