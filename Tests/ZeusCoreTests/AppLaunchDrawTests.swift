import Testing
@testable import ZeusCore

struct AppLaunchDrawTests {
    @Test func openingAndSwitchingNameTheApp() throws {
        let opening = try #require(AppLaunchDraw.from(summary: "Open Safari"))
        let switching = try #require(AppLaunchDraw.from(summary: "Switch to Music"))
        func cards(_ plan: AppLaunchDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(opening) == ["App", "Safari", "Open"])
        #expect(cards(switching) == ["App", "Music", "Switch"])
        #expect(opening.boltCaption(at: 0) == "App")
        #expect(opening.boltCaption(at: 100) == "Open")
        #expect(switching.boltCaption(at: ExplainBeatSchedule.gap) == "Music")
        #expect(opening.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
    }

    @Test func aSiteSummaryIsNotAnApp() {
        #expect(AppLaunchDraw.from(summary: "Open example.com") == nil)
        #expect(AppLaunchDraw.from(summary: "Open ") == nil)
        #expect(AppLaunchDraw.from(summary: "Research: tides") == nil)
        #expect(AppLaunchDraw.plan(name: "  ", switching: false) == nil)
    }
}
