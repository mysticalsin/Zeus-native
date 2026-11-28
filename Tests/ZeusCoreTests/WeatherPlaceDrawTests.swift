import Testing
@testable import ZeusCore

struct WeatherPlaceDrawTests {
    private func cards(_ plan: WeatherPlaceDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theCityAndUnitsFollowForecast() {
        let usual = WeatherPlaceDraw.plan(place: "Sao Paulo", units: "\u{00B0}C")
        #expect(cards(usual) == ["Forecast", "Place: Sao Paulo", "Units: \u{00B0}C"])
        #expect(WeatherPlaceAsk.line(place: "Sao Paulo", units: "\u{00B0}C") == "The forecast is for Sao Paulo, and the units are \u{00B0}C.")
        #expect(usual.boltCaption(at: 0) == "Forecast")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Units: \u{00B0}C")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(cards(WeatherPlaceDraw.plan(place: "None", units: "\u{00B0}F")) == ["Forecast", "Place: None", "Units: \u{00B0}F"])
        #expect(WeatherPlaceAsk.line(place: "None", units: "\u{00B0}F") == "The forecast has no city, and the units are \u{00B0}F.")
        #expect(cards(WeatherPlaceDraw.plan(place: "London", units: "Kelvin")) == ["Forecast", "Can't"])
        #expect(WeatherPlaceAsk.line(place: String(repeating: "A", count: 53), units: "\u{00B0}C") == "I can't read where the forecast is from.")
    }

    @Test func theSkyStaysOffThisAsk() {
        #expect(WeatherPlaceAsk.matches("where's the forecast from"))
        #expect(WeatherPlaceAsk.matches("Hey Zeus, which temperature units?"))
        #expect(WeatherPlaceAsk.matches("weather place settings"))
        #expect(!WeatherPlaceAsk.matches("what's the weather"))
        #expect(!WeatherPlaceAsk.matches("the forecast"))
        #expect(!WeatherPlaceAsk.matches("how's home styled"))
    }
}
