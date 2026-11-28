import Testing
@testable import ZeusCore

struct TimerDrawTests {
    @Test func aTimerShowsTheSameLengthTheVoiceSays() throws {
        #expect(TimerDraw.duration(300) == "5 minutes")
        #expect(TimerDraw.duration(3600) == "1 hour")
        #expect(TimerDraw.duration(90) == "1 minute 30 seconds")
        #expect(TimerDraw.duration(45) == "45 seconds")
        #expect(TimerDraw.duration(0) == "0 seconds")
        #expect(TimerDraw.duration(-4) == "0 seconds")
        let plan = try #require(TimerDraw.plan(seconds: 300))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Timer", "5 minutes"])
        #expect(plan.boltCaption(at: 0) == "Timer")
        #expect(plan.boltCaption(at: 100) == "5 minutes")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(TimerDraw.plan(seconds: -1) == nil)
    }

    @Test func cancellingShowsOnlyCancelled() {
        let plan = TimerDraw.cancelled()
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Cancelled"])
        #expect(plan.length.isEmpty)
        #expect(plan.boltCaption(at: 100) == "Cancelled")
    }
}
