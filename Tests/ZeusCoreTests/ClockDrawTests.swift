import Foundation
import Testing
@testable import ZeusCore

struct ClockDrawTests {
    private func cards(_ plan: ClockDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    private func at(hour: Int, minute: Int, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour, minute: minute))!
    }

    @Test func theClockDrawsTheDigitsThenTheHalf() {
        let plan = ClockDraw.plan(time: "2:47", period: "PM")
        #expect(plan.map(cards) == ["Clock", "2:47", "PM"])
        #expect(ClockAsk.line(time: "2:47", period: "PM") == "It's 2:47 PM.")
        #expect(plan?.boltCaption(at: 0) == "Clock")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "2:47")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "PM")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(ClockDraw.plan(time: " ", period: "PM") == nil)
        #expect(ClockDraw.plan(time: "2:47", period: "Noon") == nil)
        #expect(ClockDraw.plan(time: "25:00", period: "PM") == nil)
        let zone = TimeZone(identifier: "America/Sao_Paulo")!
        let afternoon = ClockAsk.parts(now: at(hour: 14, minute: 47, timeZone: zone), timeZone: zone)
        #expect(afternoon.time == "2:47")
        #expect(afternoon.period == "PM")
        #expect(ClockAsk.line(time: afternoon.time, period: afternoon.period) == "It's 2:47 PM.")
        let midnight = ClockAsk.parts(now: at(hour: 0, minute: 0, timeZone: zone), timeZone: zone)
        #expect(midnight.time == "12:00")
        #expect(midnight.period == "AM")
        let noon = ClockAsk.parts(now: at(hour: 12, minute: 1, timeZone: zone), timeZone: zone)
        #expect(noon.time == "12:01")
        #expect(noon.period == "PM")
    }

    @Test func aMeetingTimeIsNotTheWallClock() {
        #expect(ClockAsk.matches("what time is it"))
        #expect(ClockAsk.matches("Hey Zeus, what's the time?"))
        #expect(ClockAsk.matches("current time"))
        #expect(ClockAsk.matches("tell me the time"))
        #expect(!ClockAsk.matches("what time is the meeting"))
        #expect(!ClockAsk.matches("what's next"))
        #expect(!ClockAsk.matches("what's the weather"))
        #expect(!ClockAsk.matches("join my next meeting"))
        #expect(!ClockAsk.matches("new reminder: pay rent"))
    }
}
