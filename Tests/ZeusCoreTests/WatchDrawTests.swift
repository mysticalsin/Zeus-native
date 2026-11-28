import Testing
@testable import ZeusCore

struct WatchDrawTests {
    @Test func aWatchShowsWhatItIsWaitingFor() throws {
        let plan = try #require(WatchDraw.plan(label: "build", waiting: "Build finishes"))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Watching", "build", "Build finishes"])
        #expect(cards.allSatisfy { !$0.contains("pgrep") && !$0.contains("swift-build") })
        #expect(plan.boltCaption(at: 0) == "Watching")
        #expect(plan.boltCaption(at: 100) == "Build finishes")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        let appears = try #require(WatchDraw.plan(label: "Preview", waiting: "Appears"))
        #expect(appears.boltCaption(at: 100) == "Appears")
    }

    @Test func aBlankWatchIsNotDrawnAndStoppingNamesNothing() {
        #expect(WatchDraw.plan(label: "  ", waiting: "Build finishes") == nil)
        #expect(WatchDraw.plan(label: "build", waiting: " ") == nil)
        let stopped = WatchDraw.stopped()
        let cards = stopped.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Stopped"])
        #expect(stopped.label.isEmpty)
        #expect(stopped.boltCaption(at: 100) == "Stopped")
    }
}
