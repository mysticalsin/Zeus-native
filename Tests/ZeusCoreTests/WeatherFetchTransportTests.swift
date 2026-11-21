import Foundation
import Testing
@testable import ZeusCore

@Suite("Weather fetch transport")
struct WeatherFetchTransportTests {
    @Test func aCrossHostRedirectIsRefused() {
        let original = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=Lisbon")!
        let other = URL(string: "https://other.example/collect?name=Lisbon")!
        let same = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=Porto")!
        #expect(WeatherSnapshot.redirected(other, from: original) == nil)
        #expect(WeatherSnapshot.redirected(same, from: original) == same)
    }
}
