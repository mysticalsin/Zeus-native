import Foundation
import Testing
@testable import ZeusCore

@Suite("Weather precise location persistence")
struct WeatherPreciseLocationPersistenceTests {
    private func fresh() throws -> UserDefaults {
        let name = NSTemporaryDirectory() + "zeus.weather-precise.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aStoredPreciseLocationSurvivesACitySaveAndTheNextLoad() throws {
        let defaults = try fresh()
        defaults.set("true", forKey: WeatherSettingsDisk.locationKey)
        WeatherSettingsDisk.save(city: "Lisbon", unit: .celsius, layout: .summary, defaults: defaults)
        #expect(defaults.string(forKey: WeatherSettingsDisk.locationKey) == "true")
        let loaded = WeatherSettingsDisk.load(defaults: defaults, localeUsesUSCustomary: false)
        #expect(loaded.preciseLocation)
        #expect(loaded.city == "Lisbon")
    }

    @Test func anImportCannotTurnPreciseLocationOnAndCannotTurnItOffByOmission() throws {
        let defaults = try fresh()
        defaults.set("true", forKey: WeatherSettingsDisk.locationKey)
        let current = WeatherSettingsDisk.load(defaults: defaults, localeUsesUSCustomary: false)
        let omitted = WeatherSettingsDisk.applyingImport([WeatherSettingsDisk.cityKey: "Oslo"], onto: current)
        #expect(omitted.preciseLocation)
        let forced = WeatherSettingsDisk.applyingImport(
            [WeatherSettingsDisk.locationKey: "true"],
            onto: WeatherSettingsDisk.load(defaults: try fresh(), localeUsesUSCustomary: false)
        )
        #expect(!forced.preciseLocation)
    }
}
