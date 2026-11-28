import Foundation
import Testing
@testable import ZeusCore

struct RainDrawTests {
    private func cards(_ plan: RainDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func soonRainDrawsTheWait() {
        let plan = RainDraw.plan(minutes: 25)
        #expect(plan.map(cards) == ["Rain", "25 min"])
        #expect(RainAsk.line(minutes: 25) == "Rain in 25 minutes.")
        #expect(RainAsk.line(minutes: 1) == "Rain in 1 minute.")
        #expect(RainDraw.plan(minutes: 120).map(cards) == ["Rain", "2 hr"])
        #expect(RainAsk.line(minutes: 120) == "Rain in 2 hours.")
        #expect(plan?.boltCaption(at: 0) == "Rain")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "25 min")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(RainDraw.plan(minutes: 0) == nil)
        #expect(RainDraw.plan(minutes: 400) == nil)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(RainAsk.minutes(until: now.addingTimeInterval(25 * 60), now: now) == 25)
        #expect(RainAsk.minutes(until: now, now: now) == nil)
    }

    @Test func rainThatStartedDrawsNowAndTheForecastIsNotThisAsk() {
        #expect(cards(RainDraw.now()) == ["Rain", "Now"])
        #expect(cards(RainDraw.none()) == ["Rain", "None"])
        #expect(cards(RainDraw.notReady()) == ["Rain", "Wait"])
        #expect(RainAsk.now == "It's raining.")
        #expect(RainAsk.none == "No rain is coming.")
        #expect(RainAsk.notReady == "I don't have a rain forecast.")
        #expect(RainAsk.matches("will it rain"))
        #expect(RainAsk.matches("Hey Zeus, when will it rain?"))
        #expect(RainAsk.matches("is it raining"))
        #expect(!RainAsk.matches("what's the weather"))
        #expect(!RainAsk.matches("what's the forecast"))
        #expect(!RainAsk.matches("what's on my shelf"))
        #expect(!RainAsk.matches("how's the brightness"))
    }
}
