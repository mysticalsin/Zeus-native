import SwiftUI
import ZeusCore

/// Sizes of the customise bar under Home's cards.
enum HomeCustomize {
    static let rowHeight: CGFloat = 28
    static let barHeight: CGFloat = rowHeight * 2 + 6
}

extension HomeWidgetKind {
    /// The glass tint each widget sits on (the four originals keep theirs).
    var tint: Color {
        switch self {
        case .music, .worldClock, .agents: GlanceTint.cool
        case .focus, .agenda, .note: GlanceTint.neutral
        case .weather, .clock, .battery: GlanceTint.slate
        case .calendar, .month, .countdown: GlanceTint.copper
        }
    }
}

/// One Home card: the widget a slot holds, drawn in the variant its setting names.
struct HomeWidgetCard: View {
    let kind: HomeWidgetKind
    let topBar: TopBarModel
    var agentSummary = "No agents running"

    private var variant: String { kind.resolveVariant(SettingsStore.shared.string(kind.variantSettingID)) }

    var body: some View {
        switch kind {
        case .music: music
        case .focus: focus
        case .weather: weather
        case .calendar: calendar
        case .clock: clock
        case .worldClock: worldClock
        case .month: monthCard
        case .agenda: agendaCard
        case .countdown: countdown
        case .note: note
        case .battery: battery
        case .agents: agents
        }
    }

    // MARK: Shared bits

    private func caption(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(GlanceType.title).foregroundStyle(Color.white.opacity(0.70))
            Text(subtitle).font(GlanceType.title).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func openCalendar() -> some View {
        GlanceRoundButton(symbol: "arrow.up.right", filled: true, label: "Open Calendar") { topBar.selectedTab = .calendar }
    }

    private var animatesFreely: Bool { !TopBarStyle.isSnapshot && !Motion.reduced }

    // MARK: Music (art, disc, cassette, wave)

    private var music: some View {
        let playing = topBar.nowPlaying
        return GlanceCard(tint: kind.tint) {
            switch variant {
            case "disc": musicDisc(playing)
            case "cassette": musicCassette(playing)
            case "wave": musicWave(playing)
            case "lyrics": musicLyrics(playing)
            default: musicArt(playing)
            }
        }
    }

    private func transport(_ playing: NowPlaying?, size: CGFloat = 26) -> some View {
        HStack {
            GlanceRoundButton(symbol: "backward.fill", size: size, label: "Previous track") { topBar.musicCommand(.previous) }
            Spacer()
            GlanceRoundButton(symbol: playing?.isPlaying == true ? "pause.fill" : "play.fill", size: size + 2, filled: true,
                              label: playing?.isPlaying == true ? "Pause" : "Play") { topBar.musicCommand(.playPause) }
            Spacer()
            GlanceRoundButton(symbol: "forward.fill", size: size, label: "Next track") { topBar.musicCommand(.next) }
        }
    }

    private func titles(_ playing: NowPlaying?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playing?.title ?? "Nothing playing").font(GlanceType.media).foregroundStyle(.white).lineLimit(1)
            if let artist = playing?.artist, !artist.isEmpty {
                Text(artist).font(GlanceType.title).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
            }
        }
    }

    private func musicArt(_ playing: NowPlaying?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                AlbumTile(playing: playing, size: 48).accessibilityHidden(true)
                titles(playing)
            }
            Spacer(minLength: 0)
            transport(playing)
        }
    }

    private func musicDisc(_ playing: NowPlaying?) -> some View {
        HStack(spacing: 10) {
            TickingView(interval: 1.0 / 24.0, paused: !(playing?.isPlaying ?? false) || !animatesFreely) { context in
                let angle = animatesFreely ? context.date.timeIntervalSinceReferenceDate * 48 : 0
                VinylDisc(playing: playing).rotationEffect(.degrees(angle))
            }
            .frame(width: 74, height: 74)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                titles(playing)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    GlanceRoundButton(symbol: playing?.isPlaying == true ? "pause.fill" : "play.fill", size: 28, filled: true,
                                      label: playing?.isPlaying == true ? "Pause" : "Play") { topBar.musicCommand(.playPause) }
                    GlanceRoundButton(symbol: "forward.fill", size: 26, label: "Next track") { topBar.musicCommand(.next) }
                }
            }
        }
    }

    private func musicCassette(_ playing: NowPlaying?) -> some View {
        VStack(spacing: 6) {
            TickingView(interval: 1.0 / 24.0, paused: !(playing?.isPlaying ?? false) || !animatesFreely) { context in
                CassetteTape(title: playing?.title ?? "Nothing playing", artist: playing?.artist ?? "",
                             angle: animatesFreely ? context.date.timeIntervalSinceReferenceDate * 90 : 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(playing.map { "\($0.title), \($0.artist)" } ?? "Nothing playing")
            transport(playing, size: 22)
        }
    }

    private func musicLyrics(_ playing: NowPlaying?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text([playing?.title ?? "Nothing playing", playing?.artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                .font(GlanceType.title).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1).padding(.trailing, 30)
            LyricsView(playing: playing, rows: 3, rowHeight: 24, fontSize: 11.5)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            GlanceRoundButton(symbol: playing?.isPlaying == true ? "pause.fill" : "play.fill", size: 22, filled: true,
                              label: playing?.isPlaying == true ? "Pause" : "Play") { topBar.musicCommand(.playPause) }
        }
    }

    private func musicWave(_ playing: NowPlaying?) -> some View {
        let tint = playing.map { ArtworkStore.shared.tint(for: $0, saturation: 0.7, brightness: 0.95) } ?? Color.white.opacity(0.4)
        return VStack(alignment: .leading, spacing: 0) {
            titles(playing)
            Spacer(minLength: 0)
            LevelBars(count: 16, color: tint, active: playing?.isPlaying == true, level: nil, height: 30)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            transport(playing, size: 22)
        }
    }

    // MARK: Focus

    private var focus: some View {
        let timer = topBar.focus
        let running = timer.phase != .idle
        return GlanceCard(tint: kind.tint) {
            TickingView(interval: 1) { context in
                let seconds = Int(running ? timer.remaining(at: context.date) : 25 * 60)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        caption("Focus", running ? (timer.phase == .rest ? "Break" : "Focusing") : "Ready")
                        Spacer()
                        GlanceRoundButton(symbol: running ? "stop.fill" : "play.fill", filled: true, label: running ? "Stop focus" : "Start focus") {
                            if running { topBar.focus.stop() } else { topBar.focus.start() }
                        }
                    }
                    Spacer(minLength: 0)
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(GlanceType.numeral).monospacedDigit().foregroundStyle(.white)
                        .accessibilityLabel("\(seconds / 60) minutes \(seconds % 60) seconds")
                }
            }
        }
    }

    // MARK: Weather (summary, hourly curve, days, feels like, wind)

    private var weather: some View {
        GlanceCard(tint: kind.tint) {
            if let weather = topBar.weather {
                switch variant {
                case "hourly": weatherHourly(weather)
                case "days": weatherDays(weather)
                case "feels": weatherFeels(weather)
                case "wind": weatherWind(weather)
                default: weatherSummary(weather)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    caption("Weather", "Set up weather")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var place: String { topBar.weatherPlace }

    private func weatherSummary(_ weather: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            caption("Weather", place.isEmpty ? weather.phrase : "\(place) · \(weather.phrase)")
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline) {
                Text(topBar.temperature(weather.temperature)).font(GlanceType.numeral).foregroundStyle(.white)
                Spacer()
                Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 22)).accessibilityHidden(true)
            }
        }
    }

    private func weatherHourly(_ weather: WeatherSnapshot) -> some View {
        let hours = Array(weather.hours.prefix(8))
        return VStack(alignment: .leading, spacing: 2) {
            caption("Next hours", place.isEmpty ? weather.phrase : "\(place) · \(topBar.temperature(weather.temperature))")
            Spacer(minLength: 0)
            HourlyCurve(values: hours.map(\.temperature), tint: Color(red: 0.55, green: 0.80, blue: 1.0))
                .frame(height: 38)
                .accessibilityHidden(true)
            HStack {
                if let first = hours.first { Text(first.time.formatted(ZeusDates.style.hour())).frame(maxWidth: .infinity, alignment: .leading) }
                if hours.count > 3 { Text(hours[hours.count / 2].time.formatted(ZeusDates.style.hour())).frame(maxWidth: .infinity) }
                if let last = hours.last { Text(last.time.formatted(ZeusDates.style.hour())).frame(maxWidth: .infinity, alignment: .trailing) }
            }
            .font(.system(size: 9.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.5))
        }
    }

    private func weatherDays(_ weather: WeatherSnapshot) -> some View {
        let days = Array(weather.days.prefix(4))
        return VStack(alignment: .leading, spacing: 0) {
            Text(place.isEmpty ? "Days" : "Days · \(place)").font(GlanceType.title).foregroundStyle(Color.white.opacity(0.70)).lineLimit(1)
            Spacer(minLength: 0)
            if days.isEmpty {
                Text("Forecast updating").font(GlanceType.title).foregroundStyle(Color.white.opacity(0.5))
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 3) {
                            Text(day.date.formatted(ZeusDates.style.weekday(.abbreviated))).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.6))
                            Image(systemName: WeatherSnapshot.symbol(for: day.sky, isDay: true)).symbolRenderingMode(.multicolor).font(.system(size: 15))
                            Text(topBar.temperature(day.high)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                            Text(topBar.temperature(day.low)).font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func weatherFeels(_ weather: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            caption("Feels like", place.isEmpty ? weather.phrase : "\(place) · \(weather.phrase)")
            Spacer(minLength: 0)
            Text(topBar.temperature(weather.apparent)).font(GlanceType.numeral).foregroundStyle(.white)
            Text("Actual \(topBar.temperature(weather.temperature)) · Humidity \(weather.humidity)%")
                .font(GlanceType.title).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
        }
    }

    private func weatherWind(_ weather: WeatherSnapshot) -> some View {
        let speed = topBar.useCelsius ? weather.wind : weather.wind * 0.621371
        return VStack(alignment: .leading, spacing: 0) {
            caption("Wind", place.isEmpty ? weather.phrase : place)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                WindGauge(fraction: min(1, weather.wind / 60), tint: Color(red: 0.55, green: 0.85, blue: 0.95))
                    .frame(width: 64, height: 36)
                    .accessibilityHidden(true)
                Spacer()
                Text("\(Int(speed.rounded()))").font(GlanceType.numeral).foregroundStyle(.white)
                Text(topBar.useCelsius ? "km/h" : "mph").font(GlanceType.title).foregroundStyle(Color.white.opacity(0.55))
            }
        }
    }

    // MARK: Calendar (next event, month, week, agenda)

    private var upcoming: [TopBarModel.CalendarItem] {
        let now = Date()
        return topBar.events.filter { $0.end > now }
    }

    private var calendar: some View {
        GlanceCard(tint: kind.tint) {
            switch variant {
            case "month": calendarMonth(compact: true)
            case "week": calendarWeek
            case "agenda": calendarAgenda
            default: calendarNext
            }
        }
    }

    private var calendarNext: some View {
        let now = Date()
        let next = topBar.events.first { $0.end > now && !$0.isAllDay }
        let subtitle = next.map { "\($0.title) · \($0.start.formatted(date: .omitted, time: .shortened))" } ?? "No events today"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                caption("Calendar", subtitle)
                Spacer()
                openCalendar()
            }
            Spacer(minLength: 0)
            // Glance uses the Mac's calendar (e.g. "Aban 9" on a Persian Mac).
            Text(ZeusDates.string(now, template: "MMMd")).font(GlanceType.date).foregroundStyle(.white)
        }
    }

    private func calendarMonth(compact: Bool) -> some View {
        MiniMonth(events: topBar.events + topBar.calendarEvents, open: { topBar.selectedTab = .calendar })
    }

    private var calendarWeek: some View {
        let calendar = ZeusDates.calendar()
        let today = calendar.startOfDay(for: Date())
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let days: [Date] = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let all = topBar.events + topBar.calendarEvents
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                caption("This week", "\(calendar.component(.weekOfYear, from: today)) · \(ZeusDates.string(today, template: "MMMM"))")
                Spacer()
                openCalendar()
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(days, id: \.self) { day in
                    let isToday = calendar.isDate(day, inSameDayAs: today)
                    let count = all.filter { calendar.isDate($0.start, inSameDayAs: day) }.count
                    VStack(spacing: 2) {
                        Text(day.formatted(ZeusDates.style.weekday(.narrow))).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.5))
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 12, weight: isToday ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(isToday ? Color.black : .white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(isToday ? Color.white : Color.clear))
                        Circle().fill(Color.white.opacity(count > 0 ? 0.7 : 0)).frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var calendarAgenda: some View {
        AgendaList(events: upcoming, open: { topBar.selectedTab = .calendar })
    }

    // MARK: Clock (analog, digital, elastic, blue halo)

    private var clock: some View {
        GlanceCard(tint: kind.tint) {
            switch variant {
            case "digital": clockDigital
            case "elastic": clockElastic
            case "halo": clockHalo
            default: clockAnalog
            }
        }
    }

    private var clockAnalog: some View {
        TickingView(interval: 1) { context in
            HStack(spacing: 12) {
                AnalogClock(date: context.date).frame(width: 82, height: 82).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date.formatted(ZeusDates.style.hour().minute())).font(.system(size: 22, weight: .light).monospacedDigit()).foregroundStyle(.white)
                    Text(ZeusDates.string(context.date, template: "EEEMMMd")).font(GlanceType.title).foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private var clockDigital: some View {
        TickingView(interval: 1) { context in
            VStack(alignment: .leading, spacing: 0) {
                caption("Clock", ZeusDates.string(context.date, template: "EEEEMMMd"))
                Spacer(minLength: 0)
                Text(context.date.formatted(ZeusDates.style.hour().minute())).font(GlanceType.numeral).monospacedDigit().foregroundStyle(.white)
            }
        }
    }

    private var clockElastic: some View {
        TickingView(interval: 1.0 / 24.0, paused: !animatesFreely) { context in
            let fraction = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            // A spring on every second: the digits squash, stretch and settle.
            let kick = animatesFreely ? exp(-5 * fraction) * cos(20 * fraction) : 0
            VStack(alignment: .leading, spacing: 0) {
                caption("Clock", ZeusDates.string(context.date, template: "EEEEMMMd"))
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(context.date.formatted(ZeusDates.style.hour().minute())).font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(String(format: "%02d", Calendar.current.component(.second, from: context.date)))
                        .font(.system(size: 17, weight: .medium, design: .rounded).monospacedDigit()).foregroundStyle(Color.white.opacity(0.55))
                }
                .foregroundStyle(.white)
                .scaleEffect(x: 1 - 0.05 * kick, y: 1 + 0.10 * kick, anchor: .bottomLeading)
            }
        }
    }

    private var clockHalo: some View {
        TickingView(interval: 1) { context in
            HStack(spacing: 12) {
                ZStack {
                    BlueHaloRing(date: context.date)
                    Text(context.date.formatted(ZeusDates.style.hour().minute())).font(.system(size: 17, weight: .medium).monospacedDigit()).foregroundStyle(.white)
                }
                .frame(width: 84, height: 84)
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ZeusDates.string(context.date, template: "EEEE")).font(GlanceType.media).foregroundStyle(.white)
                    Text(ZeusDates.string(context.date, template: "MMMd")).font(GlanceType.title).foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: World clock

    private var worldClock: some View {
        let zones = WorldClockZones.parse(SettingsStore.shared.string("home.worldClock.zones"))
        return GlanceCard(tint: kind.tint) {
            TickingView(interval: 1) { context in
                VStack(alignment: .leading, spacing: 3) {
                    Text("World clock").font(GlanceType.title).foregroundStyle(Color.white.opacity(0.70))
                    Spacer(minLength: 0)
                    ForEach(zones.prefix(3), id: \.identifier) { zone in
                        HStack {
                            Text(WorldClockZones.city(zone)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Text(WorldClockZones.dayOffset(zone, now: context.date)).font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.45))
                            Text(WorldClockZones.time(zone, now: context.date)).font(.system(size: 14, weight: .light).monospacedDigit()).foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }

    // MARK: Month, agenda

    private var monthCard: some View {
        GlanceCard(tint: kind.tint) { calendarMonth(compact: true) }
    }

    private var agendaCard: some View {
        GlanceCard(tint: kind.tint) { calendarAgenda }
    }

    // MARK: Countdown

    private var countdown: some View {
        let store = SettingsStore.shared
        let target = TodoQuickAdd.day(store.string("home.countdown.date"))
        let title = store.string("home.countdown.title")
        return GlanceCard(tint: kind.tint) {
            VStack(alignment: .leading, spacing: 0) {
                if let target {
                    let days = CountdownMath.days(to: target, now: Date(), calendar: ZeusDates.calendar())
                    caption(title.isEmpty ? "Countdown" : title, target.formatted(ZeusDates.style.weekday(.abbreviated).day().month(.abbreviated)))
                    Spacer(minLength: 0)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(abs(days))").font(GlanceType.numeral).monospacedDigit().foregroundStyle(.white)
                        Text(CountdownMath.unit(days)).font(GlanceType.title).foregroundStyle(Color.white.opacity(0.55))
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    caption("Countdown", "Pick a date in Settings")
                    Spacer(minLength: 0)
                    Text("Appearance › Home").font(GlanceType.title).foregroundStyle(Color.white.opacity(0.4))
                }
            }
        }
    }

    // MARK: Note

    private var note: some View {
        let text = topBar.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return GlanceCard(tint: kind.tint) {
            VStack(alignment: .leading, spacing: 4) {
                caption("Note", text.isEmpty ? "Pinned to Home" : "Pinned")
                if text.isEmpty {
                    Spacer(minLength: 0)
                    Text("Write one in the field below").font(GlanceType.title).foregroundStyle(Color.white.opacity(0.4))
                    Spacer(minLength: 0)
                } else {
                    Text(text).font(.system(size: 12.5)).foregroundStyle(.white).lineLimit(4).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                if !TopBarStyle.isSnapshot {
                    NotchTextField(text: Binding(get: { topBar.note }, set: { topBar.note = $0 }), placeholder: "Note")
                        .frame(height: 18)
                        .padding(.horizontal, 7)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }
            }
        }
    }

    // MARK: Battery

    private var battery: some View {
        GlanceCard(tint: kind.tint) {
            VStack(alignment: .leading, spacing: 0) {
                if let level = topBar.battery?.level {
                    let charging = topBar.battery?.charging == true
                    caption("Battery", charging ? "Charging" : (topBar.battery?.pluggedIn == true ? "Plugged in" : "On battery"))
                    Spacer(minLength: 0)
                    HStack(alignment: .lastTextBaseline) {
                        Text("\(level)%").font(GlanceType.numeral).monospacedDigit().foregroundStyle(level <= 20 && !charging ? Theme.danger : .white)
                        Spacer()
                        Image(systemName: charging ? "battery.100percent.bolt" : HomeStripView.batterySymbol(level))
                            .font(.system(size: 22)).foregroundStyle(level <= 20 && !charging ? Theme.danger : Theme.leaf).accessibilityHidden(true)
                    }
                    ProgressBarLine(fraction: Double(level) / 100, tint: level <= 20 && !charging ? Theme.danger : Theme.leaf).padding(.top, 6)
                } else {
                    caption("Battery", "No battery on this Mac")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Agents

    private var agents: some View {
        GlanceCard(tint: kind.tint) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    caption("Agents", agentSummary)
                    Spacer()
                    GlanceRoundButton(symbol: "arrow.up.right", filled: true, label: "Open Agents") { topBar.selectedTab = .agents }
                }
                Spacer(minLength: 0)
                Image(systemName: "bolt.fill").font(.system(size: 26)).foregroundStyle(Theme.glow).accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Pieces

/// "2026-11-24" days from now: negative once it has passed.
enum CountdownMath {
    static func days(to target: Date, now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 0
    }

    static func unit(_ days: Int) -> String {
        switch days {
        case 0: "today"
        case 1: "day to go"
        case -1: "day ago"
        case ..<0: "days ago"
        default: "days to go"
        }
    }
}

/// "Europe/London, America/New_York": the zones the world clock shows.
enum WorldClockZones {
    static func parse(_ text: String) -> [TimeZone] {
        let zones = text.split(separator: ",").compactMap { TimeZone(identifier: $0.trimmingCharacters(in: .whitespaces)) }
        return zones.isEmpty ? ["Europe/London", "America/New_York", "Asia/Tokyo"].compactMap { TimeZone(identifier: $0) } : zones
    }

    static func city(_ zone: TimeZone) -> String {
        (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier).replacingOccurrences(of: "_", with: " ")
    }

    static func time(_ zone: TimeZone, now: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = zone
        return now.formatted(style)
    }

    static func dayOffset(_ zone: TimeZone, now: Date) -> String {
        var calendar = ZeusDates.calendar()
        let here = calendar.component(.day, from: now)
        calendar.timeZone = zone
        let there = calendar.component(.day, from: now)
        if there == here { return "" }
        return there > here || (here > 25 && there < 5) ? "+1" : "-1"
    }
}

private struct ProgressBarLine: View {
    let fraction: Double
    let tint: Color
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(tint).frame(width: proxy.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 4)
    }
}

/// A vinyl record: grooves and the cover as its label.
private struct VinylDisc: View {
    let playing: NowPlaying?
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.05))
            Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            ForEach(0..<5, id: \.self) { i in
                Circle().strokeBorder(Color.white.opacity(0.05), lineWidth: 0.7).padding(CGFloat(6 + i * 5))
            }
            Circle().fill(LinearGradient(colors: [Color.white.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center))
            AlbumTile(playing: playing, size: 28).clipShape(Circle())
            Circle().fill(Color.black).frame(width: 5, height: 5)
        }
    }
}

/// A cassette with a label and two reels (the reels turn while it plays).
private struct CassetteTape: View {
    let title: String
    let artist: String
    let angle: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(red: 0.16, green: 0.16, blue: 0.19))
            RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            VStack(spacing: 3) {
                VStack(spacing: 0) {
                    Text(title).font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(Color(red: 0.25, green: 0.18, blue: 0.14)).lineLimit(1)
                    if !artist.isEmpty {
                        Text(artist).font(.system(size: 8.5, design: .rounded)).foregroundStyle(Color(red: 0.4, green: 0.3, blue: 0.24)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.95, green: 0.89, blue: 0.76)))
                .padding(.horizontal, 12)
                HStack(spacing: 38) {
                    reel
                    reel
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 12)
                .background(Capsule().fill(Color.black.opacity(0.55)).padding(.horizontal, 22))
            }
            .padding(.vertical, 5)
        }
        .frame(height: 52)
    }

    private var reel: some View {
        ZStack {
            Circle().fill(Color(red: 0.92, green: 0.92, blue: 0.94)).frame(width: 15, height: 15)
            ForEach(0..<6, id: \.self) { i in
                Rectangle().fill(Color(red: 0.2, green: 0.2, blue: 0.24)).frame(width: 1.4, height: 5).offset(y: -3.2).rotationEffect(.degrees(Double(i) * 60))
            }
            Circle().fill(Color(red: 0.2, green: 0.2, blue: 0.24)).frame(width: 4, height: 4)
        }
        .rotationEffect(.degrees(angle))
    }
}

/// The next hours' temperatures as a smooth line over a soft fill.
private struct HourlyCurve: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        Canvas { gc, size in
            guard values.count > 1, let low = values.min(), let high = values.max() else { return }
            let span = max(high - low, 1)
            let pad: CGFloat = 5
            let points: [CGPoint] = values.enumerated().map { index, value in
                CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                        y: pad + (size.height - 2 * pad) * CGFloat(1 - (value - low) / span))
            }
            var line = Path()
            line.move(to: points[0])
            for index in 1..<points.count {
                let mid = CGPoint(x: (points[index - 1].x + points[index].x) / 2, y: (points[index - 1].y + points[index].y) / 2)
                line.addQuadCurve(to: mid, control: points[index - 1])
            }
            line.addLine(to: points[points.count - 1])
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            gc.fill(fill, with: .linearGradient(Gradient(colors: [tint.opacity(0.28), tint.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            gc.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let last = points.last {
                gc.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(.white))
            }
        }
    }
}

private struct WindGauge: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        Canvas { gc, size in
            let center = CGPoint(x: size.width / 2, y: size.height - 2)
            let radius = min(size.width / 2, size.height) - 3
            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            gc.stroke(track, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            var value = Path()
            value.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * min(max(fraction, 0.02), 1)), clockwise: false)
            gc.stroke(value, with: .color(tint), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }
}

/// The blue-halo clock: a glowing ring that fills with the minute.
private struct BlueHaloRing: View {
    let date: Date

    var body: some View {
        Canvas { gc, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 6
            let seconds = Double(ZeusDates.calendar().component(.second, from: date))
            let progress = max(0.015, seconds / 60)
            let blue = Color(red: 0.30, green: 0.58, blue: 1.0)
            var ring = Path()
            ring.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
            gc.stroke(ring, with: .color(blue.opacity(0.14)), style: StrokeStyle(lineWidth: 4))
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * progress), clockwise: false)
            gc.drawLayer { layer in
                layer.addFilter(.blur(radius: 5))
                layer.stroke(arc, with: .color(blue.opacity(0.9)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
            gc.stroke(arc, with: .color(Color(red: 0.62, green: 0.82, blue: 1.0)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}

struct AnalogClock: View {
    let date: Date

    var body: some View {
        Canvas { gc, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 1.5
            gc.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                      with: .color(.white.opacity(0.22)), lineWidth: 1.2)
            for tick in 0..<12 {
                let angle = Double(tick) / 12 * 2 * .pi
                let major = tick % 3 == 0
                var path = Path()
                path.move(to: point(center, angle, radius * (major ? 0.80 : 0.88)))
                path.addLine(to: point(center, angle, radius * 0.95))
                gc.stroke(path, with: .color(.white.opacity(major ? 0.85 : 0.4)), lineWidth: major ? 1.6 : 0.9)
            }
            let parts = ZeusDates.calendar().dateComponents([.hour, .minute, .second], from: date)
            let second = Double(parts.second ?? 0), minute = Double(parts.minute ?? 0) + second / 60, hour = Double((parts.hour ?? 0) % 12) + minute / 60
            hand(&gc, center, hour / 12 * 2 * .pi, radius * 0.5, 2.6, .white)
            hand(&gc, center, minute / 60 * 2 * .pi, radius * 0.76, 1.8, .white)
            hand(&gc, center, second / 60 * 2 * .pi, radius * 0.84, 1.0, Color(red: 1.0, green: 0.45, blue: 0.35))
            gc.fill(Path(ellipseIn: CGRect(x: center.x - 2.4, y: center.y - 2.4, width: 4.8, height: 4.8)), with: .color(Color(red: 1.0, green: 0.45, blue: 0.35)))
        }
    }

    private func point(_ center: CGPoint, _ angle: Double, _ length: CGFloat) -> CGPoint {
        CGPoint(x: center.x + CGFloat(sin(angle)) * length, y: center.y - CGFloat(cos(angle)) * length)
    }

    private func hand(_ gc: inout GraphicsContext, _ center: CGPoint, _ angle: Double, _ length: CGFloat, _ width: CGFloat, _ color: Color) {
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(center, angle, length))
        gc.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

/// A month in a card: weekday initials, the days, today filled, a dot under days with events.
struct MiniMonth: View {
    let events: [TopBarModel.CalendarItem]
    let open: () -> Void

    var body: some View {
        let calendar = ZeusDates.calendar()
        let now = Date()
        let weeks = CalendarGrid.weeks(month: now, calendar: calendar)
        let month = calendar.component(.month, from: now)
        let initials = CalendarGrid.weekdayInitials(calendar: calendar)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(ZeusDates.string(now, template: "MMMM")).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.78))
                Spacer()
                Button(action: open) {
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Calendar")
            }
            HStack(spacing: 0) {
                ForEach(Array(initials.enumerated()), id: \.offset) { _, initial in
                    Text(initial).font(.system(size: 8, weight: .medium)).foregroundStyle(Color.white.opacity(0.4)).frame(maxWidth: .infinity, minHeight: 9, maxHeight: 9)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        let inMonth = calendar.component(.month, from: day) == month
                        let isToday = calendar.isDate(day, inSameDayAs: now)
                        let busy = events.contains { calendar.isDate($0.start, inSameDayAs: day) }
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 9, weight: isToday ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(isToday ? Color.black : Color.white.opacity(inMonth ? (busy ? 1 : 0.78) : 0.22))
                            .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10)
                            .background { if isToday { Circle().fill(Color.white).frame(width: 11, height: 11) } }
                            .overlay(alignment: .bottom) {
                                if busy && !isToday { Circle().fill(Color.white.opacity(0.7)).frame(width: 2.4, height: 2.4).offset(y: 1.5) }
                            }
                    }
                }
            }
        }
    }
}

/// The next events as a list: colour bar, title, time.
struct AgendaList: View {
    let events: [TopBarModel.CalendarItem]
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agenda").font(GlanceType.title).foregroundStyle(Color.white.opacity(0.70))
                    Text(events.isEmpty ? "Nothing coming up" : "\(events.count) coming up").font(GlanceType.title).foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer()
                GlanceRoundButton(symbol: "arrow.up.right", size: 24, filled: true, label: "Open Calendar", action: open)
            }
            ForEach(events.prefix(2)) { event in
                HStack(spacing: 6) {
                    Capsule().fill(Color(hex: event.colorHex)).frame(width: 3, height: 16)
                    Text(event.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Color.white.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
        }
    }
}
