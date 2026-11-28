import Testing
@testable import ZeusCore

struct AppCloseDrawTests {
    @Test func quitHideAndMissingNameTheApp() throws {
        let quit = try #require(AppCloseDraw.from(summary: "Quit Safari"))
        let hide = try #require(AppCloseDraw.from(summary: "Hide Music"))
        let closed = try #require(AppCloseDraw.from(summary: "Safari isn't open"))
        let missing = try #require(AppCloseDraw.from(summary: "Spotify isn't installed"))
        func cards(_ plan: AppCloseDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(quit) == ["Quit", "Safari"])
        #expect(cards(hide) == ["Hide", "Music"])
        #expect(cards(closed) == ["Not open", "Safari"])
        #expect(cards(missing) == ["Not installed", "Spotify"])
        #expect(quit.boltCaption(at: 0) == "Quit")
        #expect(quit.boltCaption(at: 100) == "Safari")
        #expect(quit.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(quit.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func otherSummariesAreNotAClose() {
        #expect(AppCloseDraw.from(summary: "Open Safari") == nil)
        #expect(AppCloseDraw.from(summary: "Quit ") == nil)
        #expect(AppCloseDraw.from(summary: "Research: tides") == nil)
        #expect(AppCloseDraw.from(summary: " isn't open") == nil)
    }
}
