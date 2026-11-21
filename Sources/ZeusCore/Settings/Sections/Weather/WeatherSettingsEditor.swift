import Foundation

/// The weather section sits on the top bar page, second tab. The shell placement API is not part of this value.
public enum WeatherSectionPlacement: Equatable, Sendable {
    case topbarTab(Int)
    public static let specified = WeatherSectionPlacement.topbarTab(1)
}

public enum WeatherSettingsKeys {
    public static let reused = ["topBar.weatherCity", "perm.location", "topBar.celsius", "home.variant.weather"]
}

public struct WeatherSettingsRow: Equatable, Sendable {
    public var id: String
    public var title: String
    public var helper: String
    public var accessibilityLabel: String
    public var keyboardReachable: Bool

    public init(id: String, title: String, helper: String, accessibilityLabel: String, keyboardReachable: Bool) {
        self.id = id
        self.title = title
        self.helper = helper
        self.accessibilityLabel = accessibilityLabel
        self.keyboardReachable = keyboardReachable
    }
}

/// City, units, layout, precise location, the forecast chip, and the top bar gesture, in one place.
public struct WeatherSettingsEditor: Equatable, Sendable {
    public var cityDraft: String
    public private(set) var committedCity: String
    public private(set) var unit: WeatherTemperatureUnit
    public private(set) var layout: WeatherLayoutChoice
    public private(set) var location: PreciseLocationMachine
    public private(set) var chip: WeatherChipPhase
    public private(set) var router: TopBarGestureRouter
    private var snapshot: WeatherSnapshot?
    private var place: String

    public init(cityDraft: String, committedCity: String, unit: WeatherTemperatureUnit, layout: WeatherLayoutChoice, location: PreciseLocationMachine, chip: WeatherChipPhase, router: TopBarGestureRouter, snapshot: WeatherSnapshot?, place: String) {
        self.cityDraft = cityDraft
        self.committedCity = committedCity
        self.unit = unit
        self.layout = layout
        self.location = location
        self.chip = chip
        self.router = router
        self.snapshot = snapshot
        self.place = place
    }

    public mutating func restore(city: String, unit: WeatherTemperatureUnit, layout: WeatherLayoutChoice) {
        cityDraft = city
        committedCity = city
        self.unit = unit
        self.layout = layout
    }

    public mutating func restorePreciseLocation(_ on: Bool) {
        location.restoreStored(on)
    }

    public static func fresh(localeUsesUSCustomary: Bool) -> WeatherSettingsEditor {
        WeatherSettingsEditor(
            cityDraft: "",
            committedCity: "",
            unit: WeatherTemperatureUnit.resolve(stored: nil, localeUsesUSCustomary: localeUsesUSCustomary),
            layout: .summary,
            location: PreciseLocationMachine(),
            chip: .idle("Type a city, or turn on precise location."),
            router: TopBarGestureRouter(),
            snapshot: nil,
            place: ""
        )
    }

    public var rows: [WeatherSettingsRow] {
        [
            WeatherSettingsRow(
                id: WeatherCityPolicy.settingKey,
                title: "City",
                helper: "Forecasts use this city. Nothing is requested until you apply a name.",
                accessibilityLabel: "Weather city",
                keyboardReachable: true
            ),
            WeatherSettingsRow(
                id: PreciseLocationMachine.settingKey,
                title: "Precise location",
                helper: "The location prompt appears only after you turn this on.",
                accessibilityLabel: "Precise location",
                keyboardReachable: true
            ),
            WeatherSettingsRow(
                id: WeatherTemperatureUnit.settingKey,
                title: "Units",
                helper: "Temperatures and wind use this unit.",
                accessibilityLabel: "Temperature units",
                keyboardReachable: true
            ),
            WeatherSettingsRow(
                id: WeatherLayoutChoice.settingKey,
                title: "Layout",
                helper: "Summary, hourly curve, days, feels like, or wind.",
                accessibilityLabel: "Weather layout",
                keyboardReachable: true
            ),
        ]
    }

    public mutating func commitCity() -> URL? {
        switch WeatherCityPolicy.decide(cityDraft) {
        case .empty:
            committedCity = ""
            snapshot = nil
            place = ""
            if location.readsCoordinates {
                chip = .loading("Waiting for a location.")
            } else {
                chip = .idle("Type a city, or turn on precise location.")
            }
            return nil
        case .rejected(.tooLong):
            snapshot = nil
            chip = .failed("Use a city name of 120 characters or fewer.")
            return nil
        case .rejected(.controlCharacter):
            snapshot = nil
            chip = .failed("Use a city name without control characters.")
            return nil
        case .accepted(let name):
            committedCity = name
            chip = .loading("Loading the forecast.")
            return WeatherServiceEndpoints.geocodeURL(city: name)
        }
    }

    public mutating func setUnit(_ unit: WeatherTemperatureUnit) {
        self.unit = unit
        refreshChip()
    }

    public mutating func setLayout(_ layout: WeatherLayoutChoice) {
        self.layout = layout
        refreshChip()
    }

    public mutating func enablePreciseLocation() -> PreciseLocationEffect? {
        location.send(.userEnabled)
    }

    public mutating func disablePreciseLocation() -> PreciseLocationEffect? {
        location.send(.userDisabled)
    }

    public mutating func noteAuthorization(_ authorization: LocationAuthorization) -> PreciseLocationEffect? {
        location.send(.authorization(authorization))
    }

    public mutating func present(_ phase: WeatherChipPhase) {
        if case .ready = phase { return }
        snapshot = nil
        chip = phase
    }

    public mutating func apply(snapshot: WeatherSnapshot, place: String) {
        self.snapshot = snapshot
        self.place = place
        refreshChip()
    }

    /// A typed city wins. Coordinates are read only after precise location is on and the system allowed it.
    public mutating func apply(fix: LocationFix) -> URL? {
        guard location.readsCoordinates, committedCity.isEmpty else { return nil }
        guard fix.isValid else {
            chip = .failed("That location is outside the forecast range.")
            return nil
        }
        place = fix.label
        chip = .loading("Loading the forecast.")
        return WeatherServiceEndpoints.forecastURL(latitude: fix.latitude, longitude: fix.longitude)
    }

    public mutating func receive(_ sample: TopBarPointerSample) -> TopBarGestureRoute? {
        router.receive(sample)
    }

    public mutating func accessibilitySwitchFace() -> TopBarGestureRoute? {
        router.accessibilityActivate()
    }

    private mutating func refreshChip() {
        guard let snapshot else { return }
        if let chip = WeatherChipBuilder.chip(snapshot: snapshot, place: place, unit: unit, layout: layout) {
            self.chip = .ready(chip)
        } else {
            self.chip = .failed("Weather is unavailable right now.")
        }
    }
}
