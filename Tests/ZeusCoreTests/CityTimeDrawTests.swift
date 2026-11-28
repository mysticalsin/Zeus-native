import Foundation
import Testing
@testable import ZeusCore

struct CityTimeDrawTests {
    private func cards(_ plan: CityTimeDraw) -> [String] {
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

    @Test func oneCityDrawsTheNameThenTheDigitsThenTheHalf() {
        let plan = CityTimeDraw.plan(city: "Tokyo", time: "2:47", period: "AM")
        #expect(plan.map(cards) == ["Tokyo", "2:47", "AM"])
        #expect(CityTimeAsk.line(city: "Tokyo", time: "2:47", period: "AM") == "It's 2:47 AM in Tokyo.")
        #expect(plan?.boltCaption(at: 0) == "Tokyo")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "2:47")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "AM")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(CityTimeDraw.plan(city: " ", time: "2:47", period: "AM") == nil)
        #expect(CityTimeDraw.plan(city: "Tokyo", time: "2:47", period: "Noon") == nil)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!
        let afternoon = at(hour: 14, minute: 47, timeZone: saoPaulo)
        let there = CityTimeAsk.parts(now: afternoon, timeZone: tokyo)
        #expect(there.time == "2:47")
        #expect(there.period == "AM")
        #expect(CityTimeAsk.zone(named: "Tokyo")?.identifier == "Asia/Tokyo")
        #expect(CityTimeAsk.zone(named: "são paulo")?.identifier == "America/Sao_Paulo")
        #expect(CityTimeAsk.zone(named: "new york")?.identifier == "America/New_York")
        #expect(CityTimeAsk.zone(named: "Narnia") == nil)
    }

    @Test func theWorldClockDrawsEachCityAndAMeetingIsNotThisAsk() {
        let readings = [
            CityTimeReading(city: "London", time: "5:47", period: "PM"),
            CityTimeReading(city: "New York", time: "12:47", period: "PM"),
            CityTimeReading(city: "Tokyo", time: "2:47", period: "AM"),
        ]
        let plan = CityTimeDraw.plan(readings: readings)
        #expect(plan.map(cards) == ["World", "London 5:47 PM", "New York 12:47 PM", "Tokyo 2:47 AM"])
        #expect(CityTimeAsk.line(readings: readings) == "It's 5:47 PM in London, 12:47 PM in New York, and 2:47 AM in Tokyo.")
        #expect(CityTimeAsk.line(readings: Array(readings.prefix(2))) == "It's 5:47 PM in London and 12:47 PM in New York.")
        #expect(plan?.boltCaption(at: 0) == "World")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 3) == "Tokyo 2:47 AM")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 3) == TalkDraw.Point(x: 920, y: 320))
        #expect(cards(CityTimeDraw.unknown()) == ["City", "Unknown"])
        #expect(CityTimeAsk.unknown == "I don't know that city.")
        #expect(CityTimeAsk.matches("what time is it in Tokyo"))
        #expect(CityTimeAsk.matches("Hey Zeus, what's the time in New York?"))
        #expect(CityTimeAsk.matches("time in São Paulo"))
        #expect(CityTimeAsk.city(in: "what time is it in Narnia") == "narnia")
        #expect(!CityTimeAsk.matches("what time is it"))
        #expect(!CityTimeAsk.matches("what time is the meeting"))
        #expect(!CityTimeAsk.matches("what time is it in 5 minutes"))
        #expect(!CityTimeAsk.matches("what's next"))
        #expect(CityTimeDraw.plan(readings: []) == nil)
    }
}
