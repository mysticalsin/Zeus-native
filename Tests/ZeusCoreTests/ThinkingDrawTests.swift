import Testing
@testable import ZeusCore

struct ThinkingDrawTests {
    @Test func aFillerShowsThinkingThenTheLine() throws {
        let plain = try #require(ThinkingDraw.plan(line: "One moment."))
        let longer = try #require(ThinkingDraw.plan(line: "Evolution takes a moment."))
        func cards(_ plan: ThinkingDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plain) == ["Thinking", "One moment."])
        #expect(cards(longer) == ["Thinking", "Evolution takes a moment."])
        #expect(plain.boltCaption(at: 0) == "Thinking")
        #expect(plain.boltCaption(at: 100) == "One moment.")
        #expect(plain.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plain.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankFillerIsNotDrawn() {
        #expect(ThinkingDraw.plan(line: "") == nil)
        #expect(ThinkingDraw.plan(line: " ") == nil)
        #expect(ThinkingDraw.plan(line: "\n") == nil)
    }
}
