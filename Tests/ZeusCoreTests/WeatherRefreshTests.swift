import Foundation
import Testing
@testable import ZeusCore

@Suite("Weather refresh")
struct WeatherRefreshTests {
    @Test func failureDoesNotMoveTheStamp() {
        let previous = Date(timeIntervalSince1970: 1_000)
        let now = previous.addingTimeInterval(30)
        #expect(WeatherRefresh.stamp(previous: previous, now: now, succeeded: false) == previous)
        #expect(WeatherRefresh.stamp(previous: previous, now: now, succeeded: true) == now)
    }

    @Test func aControlCharacterDoesNotBecomeAURL() {
        #expect(WeatherRefresh.geocodeURL(city: "Sao Paulo")?.absoluteString.contains("Sao") == true)
        #expect(WeatherRefresh.geocodeURL(city: "Sao\nPaulo") == nil)
        #expect(WeatherRefresh.geocodeURL(city: "") == nil)
    }

    @Test func aRecentSuccessIsNotDueUntilTheInterval() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(WeatherRefresh.due(lastSuccess: now, now: now.addingTimeInterval(60), force: false) == false)
        #expect(WeatherRefresh.due(lastSuccess: now, now: now.addingTimeInterval(WeatherRefresh.interval + 1), force: false))
        #expect(WeatherRefresh.due(lastSuccess: now, now: now, force: true))
    }
}
