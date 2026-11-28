import Testing
@testable import ZeusCore

struct WeatherDrawTests {
    private func cards(_ plan: WeatherDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aForecastDrawsTheSkyThenTheTemperature() {
        let plan = WeatherDraw.plan(phrase: "Partly cloudy", temperature: "22 degrees")
        #expect(plan.map(cards) == ["Weather", "Partly cloudy", "22 degrees"])
        #expect(plan?.boltCaption(at: 0) == "Weather")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Partly cloudy")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "22 degrees")
        #expect(plan?.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(WeatherAsk.line(degrees: 22, phrase: "Partly cloudy", place: "Lisbon") == "Partly cloudy in Lisbon, 22 degrees.")
        #expect(WeatherAsk.line(degrees: 22, phrase: "Partly cloudy", place: " ") == "Partly cloudy, 22 degrees.")
        #expect(WeatherDraw.plan(phrase: "  ", temperature: "22 degrees") == nil)
        #expect(WeatherAsk.line(degrees: 22, phrase: "\n", place: "Lisbon") == nil)
    }

    @Test func noForecastDrawsNotReadyAndAWeatherAppAskIsNotThis() {
        let idle = WeatherDraw.notReady()
        #expect(cards(idle) == ["Weather", "Not ready"])
        #expect(idle.boltCaption(at: ExplainBeatSchedule.gap) == "Not ready")
        #expect(WeatherAsk.notReady == "Weather isn't ready.")
        #expect(WeatherAsk.matches("what's the weather"))
        #expect(WeatherAsk.matches("Hey Zeus, how's the weather today?"))
        #expect(!WeatherAsk.matches("open the weather"))
        #expect(!WeatherAsk.matches("start focus"))
        #expect(!WeatherAsk.matches("what's playing"))
    }
}
