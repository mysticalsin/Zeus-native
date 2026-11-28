import Testing
@testable import ZeusCore

struct TranslationDrawTests {
    @Test func startingShowsLiveAndStoppingShowsOff() {
        let start = TranslationDraw.plan(starting: true)
        let stop = TranslationDraw.plan(starting: false)
        func cards(_ plan: TranslationDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(start) == ["Translation", "Live"])
        #expect(cards(stop) == ["Translation", "Off"])
        #expect(start.boltCaption(at: 0) == "Translation")
        #expect(start.boltCaption(at: 100) == "Live")
        #expect(stop.boltCaption(at: 100) == "Off")
        #expect(start.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(start.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }
}
