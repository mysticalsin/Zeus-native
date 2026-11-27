import Testing
@testable import ZeusCore

struct MediaDrawTests {
    @Test func eachTransportShowsItsWord() throws {
        let next = try #require(MediaDraw.plan(action: "next"))
        let pause = try #require(MediaDraw.plan(action: "pause"))
        let toggle = try #require(MediaDraw.plan(action: "Toggle"))
        func cards(_ plan: MediaDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(next) == ["Media", "Next"])
        #expect(cards(pause) == ["Media", "Paused"])
        #expect(cards(try #require(MediaDraw.plan(action: "play"))) == ["Media", "Playing"])
        #expect(cards(try #require(MediaDraw.plan(action: "previous"))) == ["Media", "Previous"])
        #expect(cards(toggle) == ["Media", "Play or pause"])
        #expect(next.boltCaption(at: 0) == "Media")
        #expect(next.boltCaption(at: 100) == "Next")
        #expect(next.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(next.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anUnknownTransportIsNotDrawn() {
        #expect(MediaDraw.plan(action: "  ") == nil)
        #expect(MediaDraw.plan(action: "volume") == nil)
        #expect(MediaDraw.plan(action: "spotify") == nil)
    }
}
