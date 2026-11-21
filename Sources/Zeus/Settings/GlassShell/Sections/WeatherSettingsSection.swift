import SwiftUI
import ZeusCore

extension WeatherSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(WeatherSettingsSection()) }
}

/// Weather controls and the forecast chip. The section is the second top bar tab.
struct WeatherSettingsSection: View {
    @State private var model = WeatherSettingsModel()

    var body: some View {
        let reduceMotion = Motion.reduced
        VStack(alignment: .leading, spacing: CGFloat(GlassSettingsMetrics.cardSpacing)) {
            preview(reduceMotion: reduceMotion)
            controlCard(model.editor.rows[0]) { cityControl }
            controlCard(model.editor.rows[1]) { locationControl }
            controlCard(model.editor.rows[2]) { unitControl }
            controlCard(model.editor.rows[3]) { layoutControl }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { model.start() }
    }

    private func preview(reduceMotion: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(GS.cardTitle)
                .foregroundStyle(GS.text)
                .accessibilityAddTraits(.isHeader)
            Group {
                if model.editor.router.face == .player {
                    playerTile
                } else {
                    WeatherChipTile(phase: model.editor.chip, reduceMotion: reduceMotion)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: PlayerWeatherTransition.duration(reduceMotion: false)), value: model.editor.router.face)
            HStack(spacing: 8) {
                faceButton("Show the player", showWeather: false)
                faceButton("Show the weather", showWeather: true)
            }
            Text("A horizontal swipe moves between the player and the weather.")
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: CGFloat(GlassSettingsMetrics.controlRow), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).fill(GS.card))
        .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
        .simultaneousGesture(previewSwipe)
    }

    private var playerTile: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(GS.text)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Player").font(GS.rowTitle).foregroundStyle(GS.text)
                Text("Swipe toward the weather to see the forecast.")
                    .font(GS.rowText)
                    .foregroundStyle(GS.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Player. Swipe toward the weather to see the forecast.")
    }

    private var previewSwipe: some Gesture {
        DragGesture(minimumDistance: 8).onEnded { value in
            model.receive(TopBarPointerSample(.trackpad(
                deltaX: value.translation.width,
                deltaY: value.translation.height,
                ended: true
            )))
        }
    }

    private func faceButton(_ title: String, showWeather: Bool) -> some View {
        Button(title) {
            let face = model.editor.router.face
            if showWeather, face == .player { _ = model.switchFace() }
            if !showWeather, face == .weather { _ = model.switchFace() }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
    }

    private func controlCard<Control: View>(_ row: WeatherSettingsRow, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(row.title).font(GS.rowTitle).foregroundStyle(GS.text)
                Spacer(minLength: 12)
                control()
            }
            Text(row.helper)
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
                .frame(minHeight: CGFloat(GlassSettingsMetrics.helperLine), alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: CGFloat(GlassSettingsMetrics.controlRow), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).fill(GS.card))
        .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var cityControl: some View {
        HStack(spacing: 8) {
            TextField("City", text: Binding(
                get: { model.editor.cityDraft },
                set: { model.editor.cityDraft = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)
            .onSubmit { model.applyCity() }
            .accessibilityLabel("Weather city")
            Button("Apply") { model.applyCity() }
                .accessibilityLabel("Apply weather city")
        }
    }

    private var locationControl: some View {
        Toggle(isOn: Binding(
            get: { model.editor.location.wantsPreciseLocation },
            set: { model.setPreciseLocation($0) }
        )) {
            Text(model.editor.location.statusLabel)
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
        }
        .toggleStyle(.switch)
        .accessibilityLabel("Precise location")
        .accessibilityValue(model.editor.location.statusLabel)
    }

    private var unitControl: some View {
        Picker("Temperature units", selection: Binding(
            get: { model.editor.unit },
            set: { model.setUnit($0) }
        )) {
            Text("Celsius").tag(WeatherTemperatureUnit.celsius)
            Text("Fahrenheit").tag(WeatherTemperatureUnit.fahrenheit)
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
        .accessibilityLabel("Temperature units")
    }

    private var layoutControl: some View {
        Picker("Weather layout", selection: Binding(
            get: { model.editor.layout },
            set: { model.setLayout($0) }
        )) {
            ForEach(WeatherLayoutChoice.allCases, id: \.self) { layout in
                Text(layout.title).tag(layout)
            }
        }
        .frame(width: 220)
        .accessibilityLabel("Weather layout")
    }
}

private struct WeatherChipTile: View {
    var phase: WeatherChipPhase
    var reduceMotion: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(GS.text)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(GS.rowTitle).foregroundStyle(GS.text)
                Text(detail).font(GS.rowText).foregroundStyle(GS.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsSpinner {
                Spacer(minLength: 8)
                ProgressView().controlSize(.small).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var showsSpinner: Bool {
        if reduceMotion { return false }
        if case .loading = phase { return true }
        return false
    }

    private var symbol: String {
        if case .ready(let chip) = phase { return chip.symbol }
        if case .failed = phase { return "exclamationmark.icloud" }
        if case .empty = phase { return "magnifyingglass" }
        return "cloud.sun"
    }

    private var title: String {
        if case .ready(let chip) = phase { return chip.reading }
        if case .loading = phase { return "Loading" }
        if case .failed = phase { return "Unavailable" }
        if case .empty = phase { return "No forecast" }
        return "Weather"
    }

    private var detail: String {
        switch phase {
        case .idle(let text), .loading(let text), .empty(let text), .failed(let text): text
        case .ready(let chip): "\(chip.place) · \(chip.detail)"
        }
    }

    private var accessibilityText: String {
        if case .ready(let chip) = phase { return chip.accessibilityLabel }
        return "\(title). \(detail)"
    }
}

@MainActor
@Observable
final class WeatherSettingsModel {
    var editor: WeatherSettingsEditor
    private let defaults: UserDefaults
    private let bridge = WeatherLocationBridge()
    private let loader: WeatherForecastLoader
    private var generation = 0
    private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let localeUsesUS = Locale.current.measurementSystem == .us
        var editor = WeatherSettingsEditor.fresh(localeUsesUSCustomary: localeUsesUS)
        let stored = WeatherSettingsDisk.load(defaults: defaults, localeUsesUSCustomary: localeUsesUS)
        editor.restore(city: stored.city, unit: stored.unit, layout: stored.layout)
        self.editor = editor
        loader = WeatherForecastLoader { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }
    }

    func start() {
        guard !started else { return }
        started = true
        bridge.onAuthorization = { [weak self] authorization in
            self?.noteAuthorization(authorization)
        }
        bridge.onFix = { [weak self] fix in
            self?.apply(fix: fix)
        }
        bridge.start()
    }

    func applyCity() {
        let url = editor.commitCity()
        persist()
        guard url != nil else { return }
        let city = editor.committedCity
        let ticket = nextTicket()
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.loader.fetch(city: city)
            self.deliver(outcome, ticket: ticket)
        }
    }

    func setUnit(_ unit: WeatherTemperatureUnit) {
        editor.setUnit(unit)
        persist()
    }

    func setLayout(_ layout: WeatherLayoutChoice) {
        editor.setLayout(layout)
        persist()
    }

    func setPreciseLocation(_ on: Bool) {
        let effect = on ? editor.enablePreciseLocation() : editor.disablePreciseLocation()
        switch effect {
        case .requestPrompt:
            bridge.requestPrompt()
        case .revealSystemSettings:
            bridge.revealSystemSettings()
        case .stopReadingLocation, nil:
            break
        }
        if editor.location.readsCoordinates, editor.committedCity.isEmpty {
            bridge.requestFix()
        }
    }

    func receive(_ sample: TopBarPointerSample) {
        _ = editor.receive(sample)
    }

    func switchFace() -> TopBarGestureRoute? {
        editor.accessibilitySwitchFace()
    }

    private func noteAuthorization(_ authorization: LocationAuthorization) {
        _ = editor.noteAuthorization(authorization)
        if editor.location.readsCoordinates, editor.committedCity.isEmpty {
            bridge.requestFix()
        }
    }

    private func apply(fix: LocationFix) {
        guard editor.apply(fix: fix) != nil else { return }
        let ticket = nextTicket()
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.loader.fetch(latitude: fix.latitude, longitude: fix.longitude, place: fix.label)
            self.deliver(outcome, ticket: ticket)
        }
    }

    private func deliver(_ outcome: WeatherFetchOutcome, ticket: Int) {
        guard ticket == generation else { return }
        switch outcome {
        case .idle(let text): editor.present(.idle(text))
        case .empty(let text): editor.present(.empty(text))
        case .failed(let text): editor.present(.failed(text))
        case .forecast(let snapshot, let place): editor.apply(snapshot: snapshot, place: place)
        }
    }

    private func persist() {
        WeatherSettingsDisk.save(city: editor.committedCity, unit: editor.unit, layout: editor.layout, defaults: defaults)
        SettingsStore.shared.set(WeatherLayoutChoice.settingKey, editor.layout.title)
    }

    private func nextTicket() -> Int {
        generation += 1
        return generation
    }
}
