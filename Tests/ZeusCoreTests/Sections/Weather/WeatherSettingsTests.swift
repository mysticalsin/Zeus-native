import Foundation
import Testing
@testable import ZeusCore

@Suite struct WeatherCityPolicyTests {
    @Test func emptyAndWhitespaceStayOffTheService() {
        #expect(WeatherCityPolicy.decide("") == .empty)
        #expect(WeatherCityPolicy.decide("   ") == .empty)
        #expect(WeatherCityPolicy.decide("\n\t") == .empty)
        #expect(WeatherCityPolicy.decide("  Lisbon  ") == .accepted("Lisbon"))
        #expect(WeatherCityPolicy.settingKey == "topBar.weatherCity")
        #expect(WeatherCityPolicy.maxLength == 120)
    }

    @Test func lengthBoundaryAcceptsOneHundredTwenty() {
        for count in 0...130 {
            let raw = String(repeating: "a", count: count)
            switch WeatherCityPolicy.decide(raw) {
            case .empty:
                #expect(count == 0)
            case .accepted(let city):
                #expect(count >= 1 && count <= 120)
                #expect(city.count == count)
            case .rejected(let reason):
                #expect(count == 121 || count > 120)
                #expect(reason == .tooLong(count))
            }
        }
        let padded = " " + String(repeating: "b", count: 120) + " "
        #expect(WeatherCityPolicy.decide(padded) == .accepted(String(repeating: "b", count: 120)))
        #expect(WeatherCityPolicy.decide(" " + String(repeating: "b", count: 121)) == .rejected(.tooLong(121)))
    }

    @Test func controlCharactersAreRejectedAfterTrim() {
        let controls: [Unicode.Scalar] = [Unicode.Scalar(0x01)!, Unicode.Scalar(0x07)!, "\n", "\r", Unicode.Scalar(0x7F)!]
        for scalar in controls {
            let raw = "Li\(Character(scalar))sbon"
            #expect(WeatherCityPolicy.decide(raw) == .rejected(.controlCharacter))
        }
        #expect(WeatherCityPolicy.decide("\nLisbon\n") == .accepted("Lisbon"))
        #expect(WeatherCityPolicy.decide("São Paulo") == .accepted("São Paulo"))
        #expect(WeatherCityPolicy.decide("東京") == .accepted("東京"))
    }
}

@Suite struct WeatherTemperatureUnitTests {
    @Test func storedBoolAndLocaleKeepTheExistingDefault() {
        #expect(WeatherTemperatureUnit.settingKey == "topBar.celsius")
        #expect(WeatherTemperatureUnit.resolve(stored: nil, localeUsesUSCustomary: false) == .celsius)
        #expect(WeatherTemperatureUnit.resolve(stored: nil, localeUsesUSCustomary: true) == .fahrenheit)
        #expect(WeatherTemperatureUnit.resolve(stored: true, localeUsesUSCustomary: true) == .celsius)
        #expect(WeatherTemperatureUnit.resolve(stored: false, localeUsesUSCustomary: false) == .fahrenheit)
        #expect(WeatherTemperatureUnit.celsius.stored == true)
        #expect(WeatherTemperatureUnit.fahrenheit.stored == false)
    }

    @Test func knownTemperaturesAndNonFiniteValues() {
        #expect(WeatherTemperatureUnit.degrees(celsius: -40, unit: .fahrenheit) == -40)
        #expect(WeatherTemperatureUnit.degrees(celsius: 0, unit: .fahrenheit) == 32)
        #expect(WeatherTemperatureUnit.degrees(celsius: 100, unit: .fahrenheit) == 212)
        #expect(WeatherTemperatureUnit.degrees(celsius: 21.4, unit: .celsius) == 21)
        #expect(WeatherTemperatureUnit.degrees(celsius: 21.4, unit: .fahrenheit) == 71)
        #expect(WeatherTemperatureUnit.degrees(celsius: 0.5, unit: .celsius) == 1)
        #expect(WeatherTemperatureUnit.degrees(celsius: -0.5, unit: .celsius) == -1)
        #expect(WeatherTemperatureUnit.degrees(celsius: .nan, unit: .celsius) == nil)
        #expect(WeatherTemperatureUnit.degrees(celsius: .infinity, unit: .fahrenheit) == nil)
        #expect(WeatherTemperatureUnit.degrees(celsius: -.infinity, unit: .celsius) == nil)
    }

    @Test func integerCelsiusRoundTripsAndFahrenheitFollowsTheSameRounding() {
        for celsius in -80...80 {
            let value = Double(celsius)
            #expect(WeatherTemperatureUnit.degrees(celsius: value, unit: .celsius) == celsius)
            let fahrenheit = Int((value * 9 / 5 + 32).rounded())
            #expect(WeatherTemperatureUnit.degrees(celsius: value, unit: .fahrenheit) == fahrenheit)
        }
    }

    @Test func windUsesKilometersOrMiles() {
        #expect(WeatherTemperatureUnit.wind(kilometersPerHour: 10, unit: .celsius) == 10)
        #expect(WeatherTemperatureUnit.wind(kilometersPerHour: 12.5, unit: .celsius) == 13)
        #expect(WeatherTemperatureUnit.wind(kilometersPerHour: 10, unit: .fahrenheit) == 6)
        #expect(WeatherTemperatureUnit.wind(kilometersPerHour: .nan, unit: .celsius) == nil)
        #expect(WeatherTemperatureUnit.celsius.windSuffix == "km/h")
        #expect(WeatherTemperatureUnit.fahrenheit.windSuffix == "mph")
    }
}

@Suite struct WeatherLayoutChoiceTests {
    @Test func layoutsMatchTheExistingHomeVariant() {
        #expect(WeatherLayoutChoice.settingKey == "home.variant.weather")
        #expect(WeatherLayoutChoice.settingKey == HomeWidgetKind.weather.variantSettingID)
        #expect(WeatherLayoutChoice.allCases.map(\.rawValue) == HomeWidgetKind.weather.variants.map(\.id))
        #expect(WeatherLayoutChoice.allCases.map(\.title) == HomeWidgetKind.weather.variants.map(\.title))
        #expect(WeatherLayoutChoice.resolve(nil) == .summary)
        #expect(WeatherLayoutChoice.resolve("") == .summary)
        #expect(WeatherLayoutChoice.resolve("nope") == .summary)
        #expect(WeatherLayoutChoice.resolve("hourly") == .hourly)
        #expect(WeatherLayoutChoice.resolve("Hourly curve") == .hourly)
        #expect(WeatherLayoutChoice.resolve("Feels like") == .feels)
        #expect(WeatherLayoutChoice.resolve("Wind") == .wind)
    }
}

@Suite struct PreciseLocationMachineTests {
    @Test func aFreshMachineDoesNotPromptOrRead() {
        let machine = PreciseLocationMachine()
        #expect(machine.settingKey == "perm.location")
        #expect(machine.phase == .off)
        #expect(machine.readsCoordinates == false)
        #expect(machine.showsPrompt == false)
        #expect(machine.statusLabel == "Optional")
        #expect(machine.wantsPreciseLocation == false)
    }

    @Test func thePromptAppearsOnlyWhenTheUserEnablesAnUndeterminedSystem() {
        var machine = PreciseLocationMachine()
        #expect(machine.send(.userEnabled) == .requestPrompt)
        #expect(machine.phase == .prompting)
        #expect(machine.showsPrompt)
        #expect(machine.readsCoordinates == false)
        #expect(machine.statusLabel == "Asking")
        #expect(machine.send(.userEnabled) == nil)
        #expect(machine.showsPrompt)

        #expect(machine.send(.authorization(.allowed)) == nil)
        #expect(machine.phase == .using)
        #expect(machine.readsCoordinates)
        #expect(machine.showsPrompt == false)
        #expect(machine.statusLabel == "Allowed")
        #expect(machine.send(.userEnabled) == nil)
    }

    @Test func deniedAndRestrictedOpenSettingsWithoutAPrompt() {
        var denied = PreciseLocationMachine()
        _ = denied.send(.authorization(.denied))
        #expect(denied.send(.userEnabled) == .revealSystemSettings)
        #expect(denied.phase == .denied)
        #expect(denied.showsPrompt == false)
        #expect(denied.statusLabel == "Denied")
        #expect(denied.send(.userEnabled) == .revealSystemSettings)

        var restricted = PreciseLocationMachine()
        _ = restricted.send(.authorization(.restricted))
        #expect(restricted.send(.userEnabled) == .revealSystemSettings)
        #expect(restricted.phase == .restricted)
        #expect(restricted.statusLabel == "No access")
        #expect(restricted.showsPrompt == false)
    }

    @Test func anAllowedSystemStillWaitsForTheUser() {
        var machine = PreciseLocationMachine()
        #expect(machine.send(.authorization(.allowed)) == nil)
        #expect(machine.readsCoordinates == false)
        #expect(machine.showsPrompt == false)
        #expect(machine.phase == .off)
        #expect(machine.send(.userEnabled) == nil)
        #expect(machine.phase == .using)
        #expect(machine.readsCoordinates)
    }

    @Test func turningItOffStopsReadingAndAllowsALaterPrompt() {
        var machine = PreciseLocationMachine()
        #expect(machine.send(.userDisabled) == nil)
        _ = machine.send(.userEnabled)
        #expect(machine.send(.userDisabled) == .stopReadingLocation)
        #expect(machine.phase == .off)
        #expect(machine.showsPrompt == false)
        #expect(machine.send(.userEnabled) == .requestPrompt)

        _ = machine.send(.authorization(.allowed))
        #expect(machine.send(.userDisabled) == .stopReadingLocation)
        #expect(machine.readsCoordinates == false)
        #expect(machine.statusLabel == "Optional")
    }

    @Test func losingAccessWhileUsingFailsClosed() {
        var machine = PreciseLocationMachine()
        _ = machine.send(.userEnabled)
        _ = machine.send(.authorization(.allowed))
        #expect(machine.send(.authorization(.denied)) == .stopReadingLocation)
        #expect(machine.readsCoordinates == false)
        #expect(machine.phase == .denied)

        var reset = PreciseLocationMachine()
        _ = reset.send(.userEnabled)
        _ = reset.send(.authorization(.allowed))
        #expect(reset.send(.authorization(.notDetermined)) == .stopReadingLocation)
        #expect(reset.readsCoordinates == false)
        #expect(reset.showsPrompt == false)
        #expect(reset.send(.userEnabled) == .requestPrompt)
    }

    @Test func authorizationEventsNeverRaiseThePrompt() {
        let events: [PreciseLocationEvent] = [
            .userEnabled,
            .userDisabled,
            .authorization(.notDetermined),
            .authorization(.allowed),
            .authorization(.denied),
            .authorization(.restricted),
        ]
        for first in events {
            for second in events {
                for third in events {
                    checkPromptInvariant([first, second, third])
                }
            }
        }
    }

    private func checkPromptInvariant(_ sequence: [PreciseLocationEvent]) {
        var machine = PreciseLocationMachine()
        var outstanding = false
        for event in sequence {
            let effect = machine.send(event)
            if effect == .requestPrompt {
                #expect(event == .userEnabled)
                #expect(outstanding == false)
                outstanding = true
            }
            if case .authorization = event {
                #expect(effect != .requestPrompt)
            }
            if event == .userDisabled { outstanding = false }
            if case .authorization(let authorization) = event, authorization != .notDetermined {
                outstanding = false
            }
            #expect(machine.readsCoordinates == (machine.wantsPreciseLocation && machine.authorization == .allowed))
            #expect(machine.showsPrompt == (machine.wantsPreciseLocation && machine.promptOutstanding && machine.authorization == .notDetermined))
            #expect(machine.showsPrompt == (outstanding && machine.wantsPreciseLocation && machine.authorization == .notDetermined))
            if !machine.wantsPreciseLocation {
                #expect(machine.readsCoordinates == false)
                #expect(machine.showsPrompt == false)
                #expect(machine.phase == .off)
            }
        }
    }
}

@Suite struct TopBarGestureRouterTests {
    @Test func clickDoubleAndTripleStaySingleRoutes() {
        #expect(Self.settledClick(1) == .click)
        #expect(Self.settledClick(2) == .doubleClick)
        #expect(Self.settledClick(3) == .tripleClick)
        #expect(Self.settledClick(4) == .tripleClick)
        #expect(Self.settledClick(0) == .click)

        var router = TopBarGestureRouter()
        var emitted: [TopBarGestureRoute] = []
        func feed(_ kind: TopBarPointerSample.Kind) {
            if let route = router.receive(TopBarPointerSample(kind)) { emitted.append(route) }
        }
        feed(.down(clickCount: 1))
        feed(.up(clickCount: 1))
        feed(.down(clickCount: 2))
        feed(.up(clickCount: 2))
        #expect(emitted.isEmpty)
        feed(.settle(elapsed: TopBarGestureRouter.multiClickWindow))
        #expect(emitted == [.doubleClick])

        emitted.removeAll()
        feed(.down(clickCount: 1))
        feed(.up(clickCount: 1))
        feed(.down(clickCount: 2))
        feed(.up(clickCount: 2))
        feed(.down(clickCount: 3))
        feed(.up(clickCount: 3))
        feed(.settle(elapsed: TopBarGestureRouter.multiClickWindow))
        #expect(emitted == [.tripleClick])
    }

    @Test func holdMenuAndSlopDoNotAlsoClick() {
        var router = TopBarGestureRouter()
        var emitted: [TopBarGestureRoute] = []
        func feed(_ kind: TopBarPointerSample.Kind) {
            if let route = router.receive(TopBarPointerSample(kind)) { emitted.append(route) }
        }
        feed(.down(clickCount: 1))
        feed(.hold(elapsed: TopBarGestureRouter.holdSeconds - 0.001))
        feed(.up(clickCount: 1))
        feed(.settle(elapsed: TopBarGestureRouter.multiClickWindow))
        #expect(emitted == [.click])

        emitted.removeAll()
        feed(.down(clickCount: 1))
        feed(.hold(elapsed: TopBarGestureRouter.holdSeconds))
        feed(.hold(elapsed: TopBarGestureRouter.holdSeconds + 0.2))
        feed(.up(clickCount: 1))
        feed(.settle(elapsed: TopBarGestureRouter.multiClickWindow))
        #expect(emitted == [.holdMenu])

        emitted.removeAll()
        feed(.down(clickCount: 1))
        feed(.move(distance: TopBarGestureRouter.clickSlop))
        feed(.up(clickCount: 1))
        feed(.settle(elapsed: TopBarGestureRouter.multiClickWindow))
        #expect(emitted == [.click])

        emitted.removeAll()
        feed(.down(clickCount: 1))
        feed(.move(distance: TopBarGestureRouter.clickSlop + 0.01))
        feed(.hold(elapsed: TopBarGestureRouter.holdSeconds))
        feed(.up(clickCount: 1))
        feed(.settle(elapsed: TopBarGestureRouter.multiClickWindow))
        #expect(emitted.isEmpty)
    }

    @Test func rightSwipeStaysASeparateRouteOnEverySurface() {
        for surface in [TopBarGestureSurface.player, .weather, .other] {
            var router = TopBarGestureRouter(face: .player, surface: surface)
            #expect(router.receive(TopBarPointerSample(.swipeRight)) == .rightSwipe)
            #expect(router.face == .player)
            #expect(router.receive(TopBarPointerSample(.swipeRight)) == nil)
            #expect(router.receive(TopBarPointerSample(.up(clickCount: 1))) == nil)
            #expect(router.receive(TopBarPointerSample(.swipeRight)) == .rightSwipe)
        }

        var pending = TopBarGestureRouter()
        #expect(pending.receive(TopBarPointerSample(.down(clickCount: 1))) == nil)
        #expect(pending.receive(TopBarPointerSample(.up(clickCount: 1))) == nil)
        #expect(pending.receive(TopBarPointerSample(.swipeRight)) == .rightSwipe)
        #expect(pending.receive(TopBarPointerSample(.settle(elapsed: TopBarGestureRouter.multiClickWindow))) == nil)
        #expect(pending.face == .player)
    }

    @Test func trackpadSwipeMovesBetweenPlayerAndWeather() {
        let deltas = [-80.0, -36.0, -35.99, 0, 35.99, 36.0, 80.0]
        for dx in deltas {
            for dy in deltas {
                let horizontal = abs(dx) >= TopBarGestureRouter.trackpadThreshold
                    && abs(dx) >= abs(dy) * TopBarGestureRouter.axisRatio
                var player = TopBarGestureRouter(face: .player, surface: .player)
                let fromPlayer = player.receive(TopBarPointerSample(.trackpad(deltaX: dx, deltaY: dy, ended: true)))
                if dx < 0 && horizontal {
                    #expect(fromPlayer == .showWeather)
                    #expect(player.face == .weather)
                } else {
                    #expect(fromPlayer == nil)
                    #expect(player.face == .player)
                }

                var weather = TopBarGestureRouter(face: .weather, surface: .weather)
                let fromWeather = weather.receive(TopBarPointerSample(.trackpad(deltaX: dx, deltaY: dy, ended: true)))
                if dx > 0 && horizontal {
                    #expect(fromWeather == .showPlayer)
                    #expect(weather.face == .player)
                } else {
                    #expect(fromWeather == nil)
                    #expect(weather.face == .weather)
                }

                var other = TopBarGestureRouter(face: .player, surface: .other)
                #expect(other.receive(TopBarPointerSample(.trackpad(deltaX: dx, deltaY: dy, ended: true))) == nil)
                #expect(other.face == .player)
            }
        }
    }

    @Test func aPartialTrackpadScrollDoesNotSwitchUntilItEnds() {
        var router = TopBarGestureRouter()
        #expect(router.receive(TopBarPointerSample(.trackpad(deltaX: -20, deltaY: 0, ended: false))) == nil)
        #expect(router.face == .player)
        #expect(router.receive(TopBarPointerSample(.trackpad(deltaX: -20, deltaY: 0, ended: true))) == .showWeather)
        #expect(router.face == .weather)
    }

    @Test func rightSwipeCancelsATrackpadPageChange() {
        var router = TopBarGestureRouter(face: .weather, surface: .weather)
        #expect(router.receive(TopBarPointerSample(.trackpad(deltaX: 40, deltaY: 0, ended: false))) == nil)
        #expect(router.receive(TopBarPointerSample(.swipeRight)) == .rightSwipe)
        #expect(router.face == .weather)
        #expect(router.receive(TopBarPointerSample(.trackpad(deltaX: 40, deltaY: 0, ended: true))) == nil)
        #expect(router.face == .weather)
    }

    @Test func idleAndCancelDoNotInventARoute() {
        var router = TopBarGestureRouter()
        #expect(router.receive(TopBarPointerSample(.hold(elapsed: 1))) == nil)
        #expect(router.receive(TopBarPointerSample(.up(clickCount: 1))) == nil)
        #expect(router.receive(TopBarPointerSample(.settle(elapsed: 1))) == nil)
        #expect(router.receive(TopBarPointerSample(.down(clickCount: 1))) == nil)
        #expect(router.receive(TopBarPointerSample(.cancel)) == nil)
        #expect(router.receive(TopBarPointerSample(.up(clickCount: 1))) == nil)
        #expect(router.receive(TopBarPointerSample(.settle(elapsed: 1))) == nil)
    }

    @Test func accessibilitySwitchesTheSameFaces() {
        var router = TopBarGestureRouter()
        #expect(router.accessibilityActivate() == .showWeather)
        #expect(router.face == .weather)
        #expect(router.surface == .weather)
        #expect(router.accessibilityActivate() == .showPlayer)
        #expect(router.face == .player)

        var other = TopBarGestureRouter(surface: .other)
        #expect(other.accessibilityActivate() == nil)
        #expect(other.face == .player)

        var pending = TopBarGestureRouter()
        #expect(pending.receive(TopBarPointerSample(.down(clickCount: 1))) == nil)
        #expect(pending.receive(TopBarPointerSample(.up(clickCount: 1))) == nil)
        #expect(pending.accessibilityActivate() == .showWeather)
        #expect(pending.receive(TopBarPointerSample(.settle(elapsed: TopBarGestureRouter.multiClickWindow))) == nil)
    }

    @Test func reduceMotionDoesNotChangeTheRoute() {
        #expect(PlayerWeatherTransition.duration(reduceMotion: true) == 0)
        #expect(PlayerWeatherTransition.duration(reduceMotion: false) == MotionTokens.crossfadeDuration)
        var still = TopBarGestureRouter()
        var moving = TopBarGestureRouter()
        let sample = TopBarPointerSample(.swipeRight)
        #expect(still.receive(sample) == moving.receive(sample))
    }

    private static func settledClick(_ count: Int) -> TopBarGestureRoute? {
        var router = TopBarGestureRouter()
        _ = router.receive(TopBarPointerSample(.down(clickCount: count)))
        _ = router.receive(TopBarPointerSample(.up(clickCount: count)))
        return router.receive(TopBarPointerSample(.settle(elapsed: TopBarGestureRouter.multiClickWindow)))
    }
}

@Suite struct WeatherChipPreviewTests {
    @Test func layoutsReadTheMatchingForecastField() throws {
        let snapshot = try Self.fixture()
        let summary = try #require(WeatherChipBuilder.chip(snapshot: snapshot, place: "Lisbon", unit: .celsius, layout: .summary))
        #expect(summary.reading == "21°")
        #expect(summary.symbol == snapshot.symbol)
        #expect(summary.detail == "Summary · Rain")
        #expect(summary.accessibilityLabel == "Lisbon, 21°, Rain")

        let hourly = try #require(WeatherChipBuilder.chip(snapshot: snapshot, place: "Lisbon", unit: .celsius, layout: .hourly))
        #expect(hourly.reading == "21°")
        #expect(hourly.detail == "Hourly curve · Rain")

        let days = try #require(WeatherChipBuilder.chip(snapshot: snapshot, place: "Lisbon", unit: .celsius, layout: .days))
        #expect(days.reading == "25°")
        #expect(days.detail == "Days · Rain")

        let feels = try #require(WeatherChipBuilder.chip(snapshot: snapshot, place: "Lisbon", unit: .celsius, layout: .feels))
        #expect(feels.reading == "20°")
        #expect(feels.detail == "Feels like · Rain")

        let wind = try #require(WeatherChipBuilder.chip(snapshot: snapshot, place: "Lisbon", unit: .celsius, layout: .wind))
        #expect(wind.reading == "13 km/h")
        let miles = try #require(WeatherChipBuilder.chip(snapshot: snapshot, place: "Lisbon", unit: .fahrenheit, layout: .wind))
        #expect(miles.reading == "8 mph")
        let warm = try #require(WeatherChipBuilder.chip(snapshot: snapshot, place: "Lisbon", unit: .fahrenheit, layout: .summary))
        #expect(warm.reading == "71°")
    }

    @Test func aNonFiniteSnapshotDoesNotBecomeAChip() throws {
        var snapshot = try Self.fixture()
        snapshot.temperature = .nan
        #expect(WeatherChipBuilder.chip(snapshot: snapshot, place: "Lisbon", unit: .celsius, layout: .summary) == nil)
        snapshot = try Self.fixture()
        snapshot.wind = .infinity
        #expect(WeatherChipBuilder.chip(snapshot: snapshot, place: "Lisbon", unit: .celsius, layout: .wind) == nil)
    }

    @Test func theSectionReusesExistingKeysAndTheTopBarTab() throws {
        #expect(WeatherSettingsKeys.reused == ["topBar.weatherCity", "perm.location", "topBar.celsius", "home.variant.weather"])
        #expect(WeatherSectionSlot.descriptor.keys.isEmpty)
        #expect(WeatherSectionSlot.descriptor.id == "glass.weather")
        #expect(WeatherSectionPlacement.specified == .topbarTab(1))
        #expect(WeatherSectionSlot.descriptor.placement == .topbarTab(1))
        #expect(SettingsKeyReachability.outsideKeys.contains("topBar.weatherCity"))
        #expect(SettingsKeyReachability.outsideKeys.contains("topBar.celsius"))
        let root = Self.repositoryRoot()
        let catalog = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        #expect(catalog.contains("perm.location"))
        #expect(catalog.contains("home.variant.weather"))
    }

    @Test func rowsKeepAHelperAndAKeyboardLabel() {
        let editor = WeatherSettingsEditor.fresh(localeUsesUSCustomary: false)
        #expect(editor.rows.map(\.id) == ["topBar.weatherCity", "perm.location", "topBar.celsius", "home.variant.weather"])
        #expect(editor.rows.allSatisfy { !$0.helper.isEmpty && $0.keyboardReachable && !$0.accessibilityLabel.isEmpty })
        #expect(Set(editor.rows.map(\.accessibilityLabel)).count == 4)
        #expect(editor.unit == .celsius)
        #expect(WeatherSettingsEditor.fresh(localeUsesUSCustomary: true).unit == .fahrenheit)
        #expect(editor.chip == .idle("Type a city, or turn on precise location."))
    }

    private static func fixture() throws -> WeatherSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let json = """
        {"current":{"temperature_2m":21.4,"apparent_temperature":20.1,"weather_code":61,"is_day":1,"relative_humidity_2m":70,"wind_speed_10m":12.5},
         "hourly":{"time":[1800000000],"temperature_2m":[21],"weather_code":[61],"precipitation_probability":[80]},
         "daily":{"time":[1800000000],"weather_code":[61],"temperature_2m_max":[25.0],"temperature_2m_min":[15.0]}}
        """
        return try WeatherSnapshot.decode(Data(json.utf8), now: now)
    }

    private static func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        while url.path != "/" {
            let catalog = url.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift")
            if FileManager.default.fileExists(atPath: catalog.path) { return url }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
    }
}

@Suite struct WeatherForecastServiceTests {
    @Test func anEmptyOrRejectedCityDoesNotCallTheService() async {
        let box = HitBox()
        let loader = WeatherForecastLoader { _ in
            box.hit = true
            return Data()
        }
        let blank = await loader.load(city: "  ", unit: .celsius, layout: .summary)
        let rejected = await loader.load(city: String(repeating: "a", count: 121), unit: .celsius, layout: .summary)
        #expect(box.hit == false)
        #expect(blank == .idle("Type a city, or turn on precise location."))
        #expect(rejected == .failed("Use a city name of 120 characters or fewer."))
    }

    @Test func cityResolvesThroughTheLiveForecastService() async throws {
        let box = URLBox()
        let loader = WeatherForecastLoader { url in
            box.urls.append(url)
            if url.absoluteString.contains("search") {
                let body = #"{"results":[{"name":"Lisbon","latitude":38.722,"longitude":-9.139}]}"#
                return Data(body.utf8)
            }
            let body = """
            {"current":{"temperature_2m":21.4,"apparent_temperature":20.1,"weather_code":61,"is_day":1,"relative_humidity_2m":70,"wind_speed_10m":12.5},
             "hourly":{"time":[1800000000],"temperature_2m":[21],"weather_code":[61],"precipitation_probability":[10]},
             "daily":{"time":[1800000000],"weather_code":[61],"temperature_2m_max":[25.0],"temperature_2m_min":[15.0]}}
            """
            return Data(body.utf8)
        }
        let phase = await loader.load(city: " Lisbon ", unit: .celsius, layout: .summary)
        let chip = try #require({ if case .ready(let chip) = phase { return chip } else { return nil } }())
        #expect(chip.place == "Lisbon")
        #expect(chip.reading == "21°")
        #expect(box.urls.count == 2)
        #expect(box.urls[0].query?.contains("name=Lisbon") == true || box.urls[0].absoluteString.contains("Lisbon"))
        let forecast = WeatherSnapshot.url(latitude: 38.722, longitude: -9.139)
        #expect(box.urls[1].absoluteString == forecast.absoluteString)
        #expect(WeatherServiceEndpoints.geocodeURL(city: "") == nil)
        #expect(WeatherServiceEndpoints.forecastURL(latitude: 38.722, longitude: -9.139) == forecast)
        #expect(WeatherPlaceDecoder.decode(Data(#"{"results":[]}"#.utf8)) == nil)
        #expect(WeatherPlaceDecoder.decode(Data("nope".utf8)) == nil)
    }

    @Test func aCoordinateOutsideTheRangeDoesNotCallTheService() async {
        let box = HitBox()
        let loader = WeatherForecastLoader { _ in
            box.hit = true
            return Data()
        }
        let outside = await loader.fetch(latitude: 91, longitude: 0, place: "North")
        #expect(box.hit == false)
        #expect(outside == .failed("That location is outside the forecast range."))
    }

    @Test func aMissingPlaceAndABrokenForecastStayVisible() async {
        let missing = WeatherForecastLoader { _ in Data(#"{"results":[]}"#.utf8) }
        let phase = await missing.load(city: "Nowhere", unit: .celsius, layout: .summary)
        #expect(phase == .empty("That city was not found."))

        let broken = WeatherForecastLoader { url in
            if url.absoluteString.contains("search") {
                return Data(#"{"results":[{"name":"Lisbon","latitude":38.7,"longitude":-9.1}]}"#.utf8)
            }
            return Data("nope".utf8)
        }
        let failed = await broken.load(city: "Lisbon", unit: .celsius, layout: .summary)
        #expect(failed == .failed("Weather is unavailable right now."))
    }
}

@Suite struct WeatherSettingsPersistenceTests {
    @Test func eachStoredKeySurvivesANewReader() {
        let suite = "zeus-weather-\(UUID().uuidString)"
        let first = UserDefaults(suiteName: suite)!
        defer { first.removePersistentDomain(forName: suite) }
        WeatherSettingsDisk.save(city: "Lisbon", unit: .fahrenheit, layout: .hourly, defaults: first)
        let second = UserDefaults(suiteName: suite)!
        let loaded = WeatherSettingsDisk.load(defaults: second, localeUsesUSCustomary: true)
        #expect(loaded.city == "Lisbon")
        #expect(loaded.unit == .fahrenheit)
        #expect(loaded.layout == .hourly)
        #expect(loaded.preciseLocation == false)
        #expect(second.string(forKey: WeatherSettingsDisk.layoutKey) == "Hourly curve")
        #expect(second.object(forKey: WeatherSettingsDisk.locationKey) == nil)
        #expect(WeatherSettingsDisk.layoutKey == "opt." + WeatherLayoutChoice.settingKey)
        #expect(WeatherSettingsDisk.cityKey == "topBar.weatherCity")
        #expect(WeatherSettingsDisk.celsiusKey == "topBar.celsius")
    }

    @Test func aFreshStoreStaysOffAndImportCannotEnablePreciseLocation() {
        let suite = "zeus-weather-fresh-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = WeatherSettingsDisk.load(defaults: defaults, localeUsesUSCustomary: false)
        #expect(fresh.city == "")
        #expect(fresh.layout == .summary)
        #expect(fresh.unit == .celsius)
        #expect(fresh.preciseLocation == false)
        let imported = WeatherSettingsDisk.applyingImport(
            [
                WeatherSettingsDisk.cityKey: "Oslo",
                WeatherSettingsDisk.celsiusKey: true,
                WeatherSettingsDisk.layoutKey: "Wind",
                WeatherSettingsDisk.locationKey: "true",
            ],
            onto: fresh
        )
        #expect(imported.city == "Oslo")
        #expect(imported.unit == .celsius)
        #expect(imported.layout == .wind)
        #expect(imported.preciseLocation == false)
        let rejected = WeatherSettingsDisk.applyingImport(
            [WeatherSettingsDisk.cityKey: String(repeating: "a", count: 121)],
            onto: fresh
        )
        #expect(rejected.city == "")
    }
}

@Suite struct WeatherSettingsEditorTests {
    @Test func committingACityLoadsAndUnitsChangeWithoutAnotherRequest() throws {
        var editor = WeatherSettingsEditor.fresh(localeUsesUSCustomary: false)
        #expect(editor.commitCity() == nil)
        editor.cityDraft = "Lisbon"
        let geocode = editor.commitCity()
        #expect(geocode == WeatherServiceEndpoints.geocodeURL(city: "Lisbon"))
        #expect(editor.chip == .loading("Loading the forecast."))
        #expect(editor.committedCity == "Lisbon")
        editor.apply(snapshot: try WeatherChipPreviewTestsFixture.make(), place: "Lisbon")
        guard case .ready(let chip) = editor.chip else {
            Issue.record("expected a ready chip")
            return
        }
        #expect(chip.reading == "21°")
        editor.setUnit(.fahrenheit)
        guard case .ready(let warm) = editor.chip else {
            Issue.record("expected the same forecast in fahrenheit")
            return
        }
        #expect(warm.reading == "71°")
        #expect(editor.commitCity() == WeatherServiceEndpoints.geocodeURL(city: "Lisbon"))
    }

    @Test func preciseLocationDoesNotFetchUntilTheUserEnablesIt() {
        var editor = WeatherSettingsEditor.fresh(localeUsesUSCustomary: true)
        let fix = LocationFix(latitude: 38.72, longitude: -9.14, label: "Lisbon")
        #expect(editor.apply(fix: fix) == nil)
        #expect(editor.chip == .idle("Type a city, or turn on precise location."))
        #expect(editor.enablePreciseLocation() == .requestPrompt)
        #expect(editor.location.showsPrompt)
        #expect(editor.apply(fix: fix) == nil)
        #expect(editor.noteAuthorization(.allowed) == nil)
        #expect(editor.location.readsCoordinates)
        #expect(editor.location.showsPrompt == false)
        let forecast = editor.apply(fix: fix)
        #expect(forecast == WeatherServiceEndpoints.forecastURL(latitude: 38.72, longitude: -9.14))
        #expect(editor.chip == .loading("Loading the forecast."))

        let outside = LocationFix(latitude: 91, longitude: 0, label: "North")
        #expect(editor.apply(fix: outside) == nil)
        #expect(editor.chip == .failed("That location is outside the forecast range."))
        #expect(LocationFix(latitude: -90, longitude: -180, label: "Corner").isValid)
        #expect(LocationFix(latitude: 90, longitude: 180, label: "Corner").isValid)
        #expect(LocationFix(latitude: -90.001, longitude: 0, label: "South").isValid == false)
        #expect(LocationFix(latitude: 0, longitude: 180.001, label: "East").isValid == false)
    }

    @Test func aTypedCityWinsAndARejectedNameDoesNotRequest() throws {
        var editor = WeatherSettingsEditor.fresh(localeUsesUSCustomary: false)
        _ = editor.enablePreciseLocation()
        _ = editor.noteAuthorization(.allowed)
        editor.cityDraft = "Lisbon"
        #expect(editor.commitCity() == WeatherServiceEndpoints.geocodeURL(city: "Lisbon"))
        let fix = LocationFix(latitude: 10, longitude: 10, label: "Elsewhere")
        #expect(editor.apply(fix: fix) == nil)
        editor.apply(snapshot: try WeatherChipPreviewTestsFixture.make(), place: "Lisbon")
        _ = editor.noteAuthorization(.denied)
        guard case .ready = editor.chip else {
            Issue.record("a city forecast stays up when location is denied")
            return
        }
        editor.cityDraft = "Bad\u{0001}Name"
        #expect(editor.commitCity() == nil)
        #expect(editor.chip == .failed("Use a city name without control characters."))
    }

    @Test func theGestureRouterIsTheEditorsRouter() {
        var editor = WeatherSettingsEditor.fresh(localeUsesUSCustomary: false)
        #expect(editor.receive(TopBarPointerSample(.swipeRight)) == .rightSwipe)
        #expect(editor.router.face == .player)
        #expect(editor.accessibilitySwitchFace() == .showWeather)
        #expect(editor.router.face == .weather)
        let sample = TopBarPointerSample(.trackpad(deltaX: 40, deltaY: 0, ended: true))
        #expect(editor.receive(sample) == .showPlayer)
        #expect(editor.router.face == .player)
    }
}

private final class HitBox: @unchecked Sendable {
    var hit = false
}

private final class URLBox: @unchecked Sendable {
    var urls: [URL] = []
}

enum WeatherChipPreviewTestsFixture {
    static func make() throws -> WeatherSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let json = """
        {"current":{"temperature_2m":21.4,"apparent_temperature":20.1,"weather_code":61,"is_day":1,"relative_humidity_2m":70,"wind_speed_10m":12.5},
         "hourly":{"time":[1800000000],"temperature_2m":[21],"weather_code":[61],"precipitation_probability":[80]},
         "daily":{"time":[1800000000],"weather_code":[61],"temperature_2m_max":[25.0],"temperature_2m_min":[15.0]}}
        """
        return try WeatherSnapshot.decode(Data(json.utf8), now: now)
    }
}
