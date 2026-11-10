import AppKit
import Observation
import SwiftUI
import ZeusCore

/// What the Settings pages read and do.
@MainActor
@Observable
final class GSContext {
    let services: OnboardingServices
    var permissions: PermissionsModel { services.permissions }
    @ObservationIgnored var restartConnection: () -> Void = {}
    @ObservationIgnored var connectionUp: () -> Bool = { true }
    @ObservationIgnored var copyLastDictation: () -> Void = {}
    @ObservationIgnored var openGuide: () -> Void = {}
    @ObservationIgnored var showLicenses: () -> Void = {}
    /// The Continuity tab in the notch (Settings › Beamer has the switch).
    @ObservationIgnored var continuityTabShown: () -> Bool = { false }
    @ObservationIgnored var setContinuityTabShown: (Bool) -> Void = { _ in }
    /// The notch's model: Appearance edits its tab row, weather place and music wings through it.
    @ObservationIgnored var topBar: TopBarModel?

    init(services: OnboardingServices) {
        self.services = services
    }

    func refresh() {
        services.refresh()
        LicenseManager.shared.refresh()
    }
}

/// One page's heading and cards.
struct GSPageView: View {
    let section: GSSection
    let navigation: GSNavigation
    let context: GSContext

    var body: some View {
        VStack(alignment: .leading, spacing: GS.cardGap) {
            SettingsUpdateBadgeRow()
            switch section {
            case .general: GeneralPage(navigation: navigation)
            case .appearance: AppearancePage(context: context)
            case .sounds: SoundsPage()
            case .notifications: GSNotificationsPage()
            case .shortcuts: ShortcutsPage()
            case .insomnia: InsomniaSettingsPage()
            case .integrations: AIConnectionsPage(context: context)
            case .murmure: MurmurePage(context: context)
            case .polyglot: PolyglotSettingsPage()
            case .dictation: DictationSettingsPage(context: context)
            case .voice: VoicePage()
            case .engine: EnginePage()
            case .iPhone: IPhonePage()
            case .features: FeaturesSettingsPage()
            case .beamer: BeamerSettingsPage(context: context)
            case .license: LicensePage(navigation: navigation)
            case .permissions: PermissionsPage(context: context)
            case .privacy: PrivacyPage(context: context)
            case .diagnostics: DiagnosticsPage(context: context)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor private var store: SettingsStore { SettingsStore.shared }

@MainActor private func bool(_ id: String) -> Binding<Bool> { store.boolBinding(id) }

private extension View {
    /// Names a pop-up for VoiceOver, which would otherwise read only the chosen value.
    func popupLabel(_ name: String) -> some View { accessibilityLabel(name) }
}

// MARK: General

private struct GeneralPage: View {
    let navigation: GSNavigation
    var body: some View {
        GSPageHeading(section: .general, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        // Window appearance and Language are not rows: the windows are drawn dark only and Zeus speaks English only.
        GSCard("Your defaults") {
            GSRow(symbol: "display.2", title: "Show the notch on", text: "Displays without a notch get a slim pill.") {
                GSPopup(selection: SettingsStore.binding("notch.displays"), options: NotchDisplayMode.allCases.map(\.rawValue)).popupLabel("Show the notch on")
            }
            GSDivider()
            GSRow(symbol: "bubble.left.and.bubble.right", title: "Default agent", text: "For new conversations opened from the notch.")
            HStack(spacing: 12) {
                agentChoice("Codex", symbol: "chevron.left.forwardslash.chevron.right")
                agentChoice("Claude Code", symbol: "asterisk")
            }
            .padding(.bottom, 8)
        }
        GSCard("Day to day") {
            GSToggleRow(symbol: "power", title: "Launch Zeus at login", text: "Ready as soon as you sign in to your Mac.", isOn: bool("general.launchAtLogin"))
            GSDivider()
            GSToggleRow(symbol: "cup.and.saucer", title: "Keep the Mac from sleeping", text: "Agents keep working. Your screen can still turn off and lock.", isOn: bool("general.keepAwake"))
            GSDivider()
            GSToggleRow(symbol: "person.2.wave.2", title: "Meeting mode", text: "Quiet sounds and private previews during calls and screen sharing.", isOn: bool("general.meetingMode"))
            GSDivider()
            GSToggleRow(symbol: "shared.with.you", title: "Show in screen sharing", text: "Off keeps Zeus windows out of screen shares and recordings.", isOn: bool("general.showInScreenSharing"))
            GSDivider()
            GSToggleRow(symbol: "hand.wave", title: "Welcome back recap", isOn: bool("general.welcomeBack"))
        }
        GSCard("Keep awake") {
            GSRow(symbol: "timer", title: "Session length", text: "How long the cup on Home keeps the Mac awake.") {
                GSPopup(selection: Binding(
                    get: { KeepAwakeLength.label(keepAwake.homeMinutes) },
                    set: { if let minutes = KeepAwakeLength.minutes(fromLabel: $0) { keepAwake.homeMinutes = minutes } }
                ), options: KeepAwakeLength.all.map(KeepAwakeLength.label)).popupLabel("Keep awake session length")
            }
            GSDivider()
            GSRow(symbol: "battery.25percent", title: "Battery floor", text: "Ends a session below this charge on battery. A notice comes first at 20%.") {
                GSPopup(selection: Binding(
                    get: { KeepAwakeRules.floorLabel(keepAwake.batteryFloor) },
                    set: { keepAwake.batteryFloor = KeepAwakeRules.floor(fromLabel: $0) }
                ), options: KeepAwakeRules.floorChoices.map(KeepAwakeRules.floorLabel)).popupLabel("Battery floor")
            }
            GSDivider()
            GSToggleRow(symbol: "thermometer.high", title: "End when the Mac gets too hot", text: "Ends a session when macOS reports a critical thermal state.", isOn: Binding(
                get: { keepAwake.endWhenHot },
                set: { keepAwake.endWhenHot = $0 }
            ))
            if let ended = keepAwake.lastEnd, ended != .timeUp {
                GSInfo(text: "Last session \(ended.text.prefix(1).lowercased() + ended.text.dropFirst()).")
            }
            GSDivider()
            GSRow(symbol: "moon.zzz", title: "Lid-closed mode", text: "Keep agents working with the lid shut: the Insomnia tab and Settings › Insomnia.") {
                Button("Open") { navigation.section = .insomnia }.buttonStyle(GSButtonStyle())
            }
        }
    }

    private var keepAwake: KeepAwakeSession { .shared }

    private func agentChoice(_ name: String, symbol: String) -> some View {
        let selected = SettingsStore.binding("general.defaultAgent").wrappedValue == name || (name == "Codex" && store.string("general.defaultAgent").isEmpty)
        return Button { store.set("general.defaultAgent", name) } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(name == "Codex" ? Color(rgb: 60, 62, 70) : Color(rgb: 217, 119, 87)))
                Text(name).font(OB.font(14.5, .semibold)).foregroundStyle(GS.text)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 17))
                    .foregroundStyle(selected ? GS.selectedText : GS.secondary)
            }
            .padding(.horizontal, 16).frame(height: 60)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? GS.selectedFill.opacity(0.6) : GS.window.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? GS.selectedText : GS.cardStroke, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: Appearance

private struct AppearancePage: View {
    let context: GSContext

    /// The notch reads the model's own `topBar.musicWings` key, not the `opt.` copy a plain store write would make.
    private var musicWingsBinding: Binding<Bool> {
        Binding(
            get: { context.topBar?.liveMusicWings ?? store.bool("topBar.musicWings") },
            set: { value in
                if let topBar = context.topBar { topBar.liveMusicWings = value } else { store.set("topBar.musicWings", value ? "true" : "false") }
            }
        )
    }

    private var physicalFinishBinding: Binding<String> {
        Binding(
            get: {
                let raw = store.string("appearance.physicalFinish")
                return raw == "Same everywhere" ? "Same all" : raw
            },
            set: { store.set("appearance.physicalFinish", $0) }
        )
    }

    var body: some View {
        GSPageHeading(section: .appearance, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        GSCard("Your look") {
            HStack(spacing: 12) {
                style("Glass", "")
                style("Physical", "")
                style("Liquid Glass", "")
            }
            .padding(.bottom, 12)
            HStack(spacing: 12) {
                style("Classic", "")
                style("Dashboard", "")
                style("Dashboard B", "")
            }
            .padding(.bottom, 10)
            GSInfo(text: "Changes apply instantly.")
            GSDivider()
            GSRow(symbol: "rectangle.3.group", title: "Home style", text: "The frame of the Home band: cards, no frame, or no frame with colour.") {
                GSPopup(selection: SettingsStore.binding("appearance.homeStyle"), options: SettingsCatalog.option("appearance.homeStyle")?.choices ?? []).popupLabel("Home style")
            }
            GSDivider()
            GSRow(symbol: "square.stack.3d.up", title: "Customize Physical", text: "In the Physical theme, give Home its own finish instead of the card finish.") {
                GSPopup(selection: physicalFinishBinding, options: SettingsCatalog.option("appearance.physicalFinish")?.choices ?? []).popupLabel("Physical finish")
            }
        }
        GSCard("Running card") {
            HStack(spacing: 12) {
                runningTheme("Wave", "")
                runningTheme("Essentials", "")
            }
            GSDivider()
            GSRow(symbol: "hand.point.up.left", title: "Open the notch on hover", text: "How long the pointer rests before it opens.") {
                GSPopup(selection: SettingsStore.binding("notch.openDelay"), options: SettingsCatalog.option("notch.openDelay")?.choices ?? []).popupLabel("Open the notch on hover")
            }
        }
        HomeAppearanceCard()
        GSCard("Card details and behavior") {
            GSToggleRow(symbol: "rectangle.topthird.inset.filled", title: "Hide the notch automatically", text: "Closes when you move the pointer away.", isOn: bool("notch.autoHide"))
            GSDivider()
            GSRow(symbol: "timer", title: "Delay before closing") {
                GSPopup(selection: SettingsStore.binding("notch.closeDelay"), options: SettingsCatalog.option("notch.closeDelay")?.choices ?? []).popupLabel("Delay before closing")
            }
        }
        GSCard("Zeus beside the pointer") {
            GSRow(symbol: "cursorarrow.rays", title: "Show Zeus beside the pointer",
                  text: "\"When I call him\" keeps your pointer clear: he appears for the talk shortcut, Hey Zeus, a voice turn or when he points, and fades out about 2 seconds after.") {
                GSPopup(selection: Binding(get: { BuddyPreference.shared.show.title },
                                           set: { value in BuddyPreference.shared.show = BuddyShow.allCases.first { $0.title == value } ?? .onCall }),
                        options: BuddyShow.allCases.map(\.title)).popupLabel("Show Zeus beside the pointer")
            }
            GSInfo(text: "The ... button on the notch has the same choice for a quick change.")
        }
        GSCard("A face for your agents") {
            HStack(spacing: 12) {
                avatar("Glyphs", "", mascot: false)
                avatar("Zeus", "", mascot: true)
            }
        }
        GSCard("A signature of light") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                let current = HaloStyle.resolve(store.string("halo.style"))
                ForEach(HaloStyle.allCases) { halo in
                    GSPictureChoice(title: halo.title, selected: current == halo,
                                    action: { store.set("halo.style", halo.rawValue) }) {
                        HaloOutline(style: halo, arm: "Medium", thickness: 1, drawn: 1, animated: current == halo).frame(width: 150, height: 81).clipped()
                    }
                }
            }
            .padding(.bottom, 6)
            GSRow(symbol: "sparkles", title: "Entrance animation") {
                GSPopup(selection: HaloChoices.entranceTitle, options: HaloChoices.entrances).popupLabel("Entrance animation")
            }
            GSDivider()
            GSRow(symbol: "bolt.fill", title: "Entrance intensity") {
                OBTickSlider(value: Binding(get: { min(max(store.double("halo.intensity"), 50), 150) }, set: { store.set("halo.intensity", String(Int($0))) }), range: 50...150, step: 10)
                    .frame(width: 260).environment(\.ob, OB.Palette.settings).accessibilityLabel("Entrance intensity")
            }
            GSDivider()
            GSRow(symbol: "speedometer", title: "Entrance speed") {
                OBTickSlider(value: Binding(get: { min(max(store.double("halo.speed"), 50), 200) }, set: { store.set("halo.speed", String(Int($0))) }), range: 50...200, step: 10)
                    .frame(width: 260).environment(\.ob, OB.Palette.settings).accessibilityLabel("Entrance speed")
            }
            GSDivider()
            GSRow(symbol: "arrow.left.and.right", title: "Halo arm width") {
                GSPopup(selection: SettingsStore.binding("halo.armWidth"), options: HaloChoices.armWidths).popupLabel("Halo arm width")
            }
            GSDivider()
            GSRow(symbol: "line.3.horizontal", title: "Light thickness") {
                OBTickSlider(value: Binding(get: { max(100, store.double("halo.thickness")) }, set: { store.set("halo.thickness", String(Int($0))) }), range: 100...200, step: 5)
                    .frame(width: 260).environment(\.ob, OB.Palette.settings).accessibilityLabel("Light thickness")
            }
            GSDivider()
            GSToggleRow(symbol: "dot.radiowaves.left.and.right", title: "Light wave to the screen edges", text: "When an agent starts, asks or finishes, a wave of light leaves the notch, ripples across the screen and fades.", isOn: bool("halo.edgeWave"))
        }
        GSCard("Small moments, softly signaled") {
            Text("Keep the visual feedback you find useful.").font(GS.rowText).foregroundStyle(GS.secondary).padding(.bottom, 4)
            Text("Everyday actions").font(OB.font(13, .semibold)).foregroundStyle(GS.secondary).padding(.top, 8)
            light("lights.battery", "battery.100.bolt", "Green gauge when plugged in", "Shows the battery level when power changes.")
            light("lights.rain", "cloud.rain", "Incoming rain alert", "A heads-up before the rain arrives.")
            light("lights.timer", "timer", "Timer light gauge", "A quiet countdown around the notch.")
            light("lights.micGlow", "mic", "Purple glow while the mic listens", "Follows your voice during a spoken reply.")
            light("lights.reminderGlow", "checklist", "Glow when a reminder is added", nil)
            light("lights.copy", "doc.on.doc", "Light sweep on copy", "A white sweep confirms a copy.")
            light("lights.shelf", "tray.and.arrow.down", "Intake light when files land", "A brief glow for Shelf drops.")
            AirDropPermissionRow()
            GSDivider()
            ScreenshotPermissionRow()
            GSDivider()
            light("lights.capsLock", "capslock", "Case-key lights (Caps Lock and Shift)", "Shows Caps Lock changes and Shift held on its own.", last: true)
            Text("Music").font(OB.font(13, .semibold)).foregroundStyle(GS.secondary).padding(.top, 14)
            GSToggleRow(symbol: "waveform", title: "Light wave while music plays", text: "A soft wave in the artwork\u{2019}s colors.", isOn: musicWingsBinding)
            GSDivider()
            light("lights.musicProgress", "circle.dashed", "Progress outline on the music preview", "The outline follows the track\u{2019}s progress.")
            light("lights.liveSpectrum", "waveform.path", "React to real sound", "The music wave follows the sound your Mac is playing. Zeus asks for System Audio Recording once, when you turn this on, and listens only while music plays.", last: true)
            GSDivider()
            GSRow(symbol: "chart.bar.fill", title: "Waves style", text: "How the Waves tab draws the spectrum. Add the tab under Top bar tabs, further down this page.") {
                GSPopup(selection: SettingsStore.binding("waves.style"), options: WaveStyle.allCases.map(\.rawValue)).popupLabel("Waves style")
            }
            GSDivider()
            GSRow(symbol: "slider.horizontal.3", title: "Sensitivity") {
                OBTickSlider(value: Binding(get: { min(max(store.double("waves.sensitivity"), 50), 200) }, set: { store.set("waves.sensitivity", String(Int($0))) }), range: 50...200, step: 10)
                    .frame(width: 260).environment(\.ob, OB.Palette.settings).accessibilityLabel("Waves sensitivity")
            }
            GSDivider()
            SpectrumPermissionRow()
        }
        // One child, so the page body stays within ViewBuilder's ten-view limit.
        Group {
            hudCard
            TopBarTabsCard(context: context)
        }
    }

    private var hudCard: some View {
        GSCard("Volume, brightness and keys") {
            light("lights.hud.volume", "speaker.wave.2", "Volume in the notch", "Level glow and wings when the output volume changes.")
            light("lights.hud.brightness", "sun.max", "Brightness in the notch", "Level glow when the built-in display brightness changes.")
            light("lights.hud.keyboard", "light.max", "Keyboard backlight in the notch", "Level glow when keyboard illumination changes. Skipped on Macs without a backlight.")
            light("lights.hud.mute", "speaker.slash", "Mute pulse", "A dim slash when the output is muted.")
            light("lights.hud.replaceSystem", "rectangle.on.rectangle", "Replace the macOS volume and brightness HUD", "Needs Accessibility in Settings \u{203A} Permissions. Without it, both HUDs can show.")
            light("lights.hud.screenEdge", "rectangle.dashed", "Screen-edge glow", "A glow runs around every screen edge and joins the notch, filled to the level.")
            light("lights.shortcutPeeks", "command", "Shortcut peeks", "Shows a card for command shortcuts. Needs Accessibility access.")
            light("lights.eventGlow", "calendar.badge.plus", "Glow when an event is added", "A cyan ribbon after you add a calendar event.", last: true)
        }
    }

    private func style(_ name: String, _ caption: String) -> some View {
        GSPictureChoice(title: name, caption: caption, selected: SettingsStore.binding("appearance.cardStyle").wrappedValue == name,
                        action: { store.set("appearance.cardStyle", name) }) {
            ThemePreview(style: name).frame(width: 400, height: 240).scaleEffect(0.38).frame(width: 152, height: 91)
        }
    }

    private func runningTheme(_ name: String, _ caption: String) -> some View {
        let current = SettingsStore.binding("appearance.runningCard").wrappedValue
        return GSPictureChoice(title: name, caption: caption, selected: current == name || (current.isEmpty && name == "Wave"),
                               action: { store.set("appearance.runningCard", name) }) {
            RunningCardMini(essentials: name == "Essentials").frame(width: 152, height: 91)
        }
    }

    private func avatar(_ name: String, _ caption: String, mascot: Bool) -> some View {
        // Avatar owns this switch (it saves the raw `avatar.alwaysInNotch` key the notch reads); a store write would make an `opt.` copy nobody reads.
        let selected = (AvatarStatus.shared.alwaysInNotch == mascot)
        return GSPictureChoice(title: name, caption: caption, selected: selected, action: { AvatarStatus.shared.alwaysInNotch = mascot }) {
            if mascot { MascotTile(pose: .working, side: 70, animated: false) } else {
                Image(systemName: "circle.hexagongrid.circle").font(.system(size: 40, weight: .light)).foregroundStyle(OB.blueLight)
            }
        }
    }

    @ViewBuilder
    private func light(_ id: String, _ symbol: String, _ title: String, _ text: String?, last: Bool = false) -> some View {
        GSToggleRow(symbol: symbol, title: title, text: text, isOn: bool(id))
        if !last { GSDivider() }
    }
}

/// Home: which widget each of the four cards shows, its style, the backdrop. The same choices as Customize Home on the notch.
private struct HomeAppearanceCard: View {
    private let symbols = ["1.square", "2.square", "3.square", "4.square"]

    var body: some View {
        GSCard("Home") {
            Text("Choose what the four Home cards show. Long-press Home or use the ... menu to change them right on the notch.")
                .font(GS.rowText).foregroundStyle(GS.secondary).padding(.bottom, 8)
            ForEach(1...4, id: \.self) { slot in
                GSRow(symbol: symbols[slot - 1], title: "Card \(slot)") {
                    GSPopup(selection: SettingsStore.binding(HomeSlots.settingID(slot: slot)), options: SettingsCatalog.option(HomeSlots.settingIDs[slot - 1])?.choices ?? [])
                }
                GSDivider()
            }
            style("clock", "Clock style", "home.variant.clock")
            GSDivider()
            style("music.note", "Music style", "home.variant.music")
            GSDivider()
            style("cloud.sun", "Weather style", "home.variant.weather")
            GSDivider()
            style("calendar", "Calendar style", "home.variant.calendar")
            GSDivider()
            GSRow(symbol: "globe", title: "World clock cities", text: "Time zone names, like Europe/London.") {
                GSTextInput(text: SettingsStore.binding("home.worldClock.zones"), placeholder: "Europe/London, Asia/Tokyo", label: "World clock cities")
            }
            GSDivider()
            GSRow(symbol: "hourglass", title: "Countdown title") {
                GSTextInput(text: SettingsStore.binding("home.countdown.title"), placeholder: "Launch day", label: "Countdown title")
            }
            GSDivider()
            GSRow(symbol: "calendar.badge.clock", title: "Countdown date", text: "A day as 2026-12-25.") {
                GSTextInput(text: SettingsStore.binding("home.countdown.date"), placeholder: "2026-12-25", label: "Countdown date")
            }
        }
        GSCard("Home backdrop") {
            let current = HomeBackdrop.resolve(SettingsStore.shared.string(HomeBackdrop.settingID))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(HomeBackdrop.allCases) { backdrop in
                    GSPictureChoice(title: backdrop.title, selected: current == backdrop,
                                    action: { SettingsStore.shared.set(HomeBackdrop.settingID, backdrop.title) }) {
                        BackdropSwatch(backdrop: backdrop, size: 76)
                    }
                }
            }
            .padding(.bottom, 6)
        }
    }

    private func style(_ symbol: String, _ title: String, _ id: String) -> some View {
        GSRow(symbol: symbol, title: title) {
            GSPopup(selection: SettingsStore.binding(id), options: SettingsCatalog.option(id)?.choices ?? [])
        }
    }
}

/// Which tabs the open notch shows and in what order, then the weather place and units. The same row the notch's
/// customise mode edits (TopBarModel.layout); a full row cannot take another tab, so those switches wait.
private struct TopBarTabsCard: View {
    let context: GSContext

    var body: some View {
        if let topBar = context.topBar {
            let full = topBar.layout.isFull()
            GSCard("Top bar tabs") {
                Text("Choose which pages the open notch shows and in what order. Home always comes first.")
                    .font(GS.rowText).foregroundStyle(GS.secondary).padding(.bottom, 4)
                ForEach(Array(TopBarTab.allCases.enumerated()), id: \.element.id) { index, tab in
                    if index > 0 { GSDivider() }
                    let shown = topBar.layout.contains(tab)
                    let blocked = !shown && full
                    GSRow(symbol: tab.symbol, title: tab.title, text: tab.help == tab.title ? nil : tab.help) {
                        HStack(spacing: 8) {
                            if shown, tab != .home {
                                arrow("chevron.up", "Move \(tab.title) earlier") { topBar.layout.move(tab, by: -1) }
                                arrow("chevron.down", "Move \(tab.title) later") { topBar.layout.move(tab, by: 1) }
                            }
                            Toggle(tab.title, isOn: Binding(get: { shown }, set: { _ in if !blocked, tab != .home { topBar.layout.toggle(tab) } }))
                                .toggleStyle(GSToggleStyle()).labelsHidden().accessibilityLabel("Show the \(tab.title) tab")
                                .disabled(tab == .home || blocked).opacity(tab == .home || blocked ? 0.5 : 1)
                        }
                    }
                }
                if full { GSInfo(text: "The row holds \(GlanceTopBar.maxTabs) tabs. Turn one off to add another.") }
            }
            GSCard("Weather") {
                GSRow(symbol: "location.magnifyingglass", title: "City", text: "Forecasts come from Open-Meteo. Only the city name is sent. Press Return to apply it.") {
                    TextField("City", text: Binding(get: { topBar.weatherCity }, set: { topBar.weatherCity = $0 }))
                        .textFieldStyle(.plain)
                        .snapshotSafeText(topBar.weatherCity, placeholder: "City")
                        .font(OB.font(13.5)).foregroundStyle(GS.text)
                        .padding(.horizontal, 10).frame(width: 220, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                        .onSubmit { topBar.refreshWeather() }
                        .accessibilityLabel("Weather city")
                }
                GSDivider()
                GSRow(symbol: "thermometer.medium", title: "Units") {
                    GSPopup(selection: Binding(get: { topBar.useCelsius ? "°C" : "°F" }, set: { topBar.useCelsius = ($0 == "°C") }),
                            options: ["°C", "°F"]).popupLabel("Temperature units")
                }
            }
        }
    }

    private func arrow(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(GS.text)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.buttonFill))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

// MARK: Sounds

private struct SoundsPage: View {
    var body: some View {
        GSPageHeading(section: .sounds, subtitle: "Choose your cues. Listen to each one before you begin.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Sound feedback") {
            GSToggleRow(symbol: "speaker.wave.2", title: "Sound feedback", text: "Short sounds when agents start, ask and finish.",
                        isOn: Binding(get: { ExtraPreferences.shared.soundsOn }, set: { ExtraPreferences.shared.soundsOn = $0 }))
            GSDivider()
            GSRow(symbol: "speaker.wave.1", title: "Volume", text: "How loud every cue plays, previews included.") {
                OBTickSlider(value: Binding(get: { Double(min(max(ExtraPreferences.shared.soundVolume, 0), 100)) },
                                            set: { ExtraPreferences.shared.soundVolume = Int($0) }), range: 0...100, step: 10)
                    .frame(width: 260).environment(\.ob, OB.Palette.settings).accessibilityLabel("Sound volume")
            }
            .disabled(!ExtraPreferences.shared.soundsOn)
            .opacity(ExtraPreferences.shared.soundsOn ? 1 : 0.5)
        }
        GSCard("Your cues") {
            cue("play.circle", "Run start", "When an agent starts a new task.", "sound.startStyle", SoundStyles.runStart, .start)
            GSDivider()
            cue("hand.raised", "Requests", "When an agent needs a permission or an answer.", "sound.approvalStyle", SoundStyles.requests, .approval)
            GSDivider()
            cue("checkmark.bubble", "Your answer", "When you approve or deny a request.", "sound.answerStyle", SoundStyles.answer, .answer)
            GSDivider()
            cue("checkmark.seal", "Completion", "The chime for a task completed successfully.", "sound.doneStyle", SoundStyles.done, .done)
            GSDivider()
            GSToggleRow(symbol: "timer", title: "Timer alarms", text: "A sound when a focus round ends.", isOn: bool("sound.timer"))
            GSDivider()
            GSToggleRow(symbol: "exclamationmark.octagon", title: "Failure sound", text: "A short sound when an agent turn fails.", isOn: bool("sound.failure"))
            GSDivider()
            GSToggleRow(symbol: "waveform", title: "Ambient loop while an agent works", text: "A quiet loop under a running agent, at half volume.", isOn: bool("sound.runningLoop"))
        }
        // These switches still gate playback (ZeusSound.play), whatever style a cue above is set to.
        GSCard("Which events play a sound") {
            GSToggleRow(symbol: "hand.raised", title: "Play the Requests cue", text: "When an agent needs a permission or an answer.",
                        isOn: Binding(get: { ExtraPreferences.shared.soundApproval }, set: { ExtraPreferences.shared.soundApproval = $0 }))
            GSDivider()
            GSToggleRow(symbol: "checkmark.seal", title: "Play the Completion chime", text: "When a task completes.",
                        isOn: Binding(get: { ExtraPreferences.shared.soundDone }, set: { ExtraPreferences.shared.soundDone = $0 }))
            GSDivider()
            GSToggleRow(symbol: "checklist", title: "Play a sound when a to-do is checked", isOn: Binding(get: { ExtraPreferences.shared.soundTodo }, set: { ExtraPreferences.shared.soundTodo = $0 }))
        }
        .disabled(!ExtraPreferences.shared.soundsOn)
        .opacity(ExtraPreferences.shared.soundsOn ? 1 : 0.5)
        GSCard("Voice cues") {
            voiceCue("ear", "Zeus is listening", "Hey Zeus heard, or the talk key went down.", \.soundListenStart, .listenStart)
            GSDivider()
            voiceCue("ear.badge.checkmark", "Zeus stopped listening", "You let go, or went quiet.", \.soundListenStop, .listenStop)
            GSDivider()
            voiceCue("checkmark.bubble", "Answer finished", "Zeus did what you asked.", \.soundVoiceDone, .voiceDone)
            GSDivider()
            voiceCue("exclamationmark.triangle", "Something went wrong", "Zeus couldn\u{2019}t hear you or couldn\u{2019}t finish.", \.soundVoiceError, .voiceError)
        }
        .disabled(!ExtraPreferences.shared.soundsOn)
        .opacity(ExtraPreferences.shared.soundsOn ? 1 : 0.5)
    }

    private func cue(_ symbol: String, _ title: String, _ text: String, _ id: String, _ options: [String], _ event: ZeusSound.Event) -> some View {
        GSRow(symbol: symbol, title: title, text: text) {
            HStack(spacing: 8) {
                GSPopup(selection: SettingsStore.binding(id), options: options).popupLabel("\(title) sound")
                preview(event, title)
            }
        }
    }

    private func voiceCue(_ symbol: String, _ title: String, _ text: String, _ key: ReferenceWritableKeyPath<ExtraPreferences, Bool>, _ event: ZeusSound.Event) -> some View {
        GSRow(symbol: symbol, title: title, text: text) {
            HStack(spacing: 8) {
                preview(event, title)
                Toggle(title, isOn: Binding(get: { ExtraPreferences.shared[keyPath: key] }, set: { ExtraPreferences.shared[keyPath: key] = $0 }))
                    .toggleStyle(GSToggleStyle()).labelsHidden().accessibilityLabel(title)
            }
        }
    }

    private func preview(_ event: ZeusSound.Event, _ title: String) -> some View {
        Button { SoundStyles.preview(event) } label: {
            Image(systemName: "speaker.wave.2").font(.system(size: 12, weight: .medium)).foregroundStyle(OB.blueText)
                .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.selectedFill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play the \(title.lowercased()) sound")
    }
}

// MARK: iPhone

private struct IPhonePage: View {
    var body: some View {
        GSPageHeading(section: .iPhone, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        GSCard {
            GSRow(symbol: "iphone", title: "iPhone app", text: "Pairing needs the ZEUS iPhone app on your phone.") {
                GSStatus(ok: false, text: "Not available")
            }
        }
    }
}

// MARK: Notifications

private struct GSNotificationsPage: View {
    private var systemNotifications: SystemNotificationService { .shared }
    var body: some View {
        GSPageHeading(section: .notifications, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        GSCard("Agent notifications") {
            // The old Permission requests and Finished tasks switches had no reader: nothing ever checked them. An agent
            // waits for the answer to a request, so it always shows; finished-task banners follow "Show system notifications".
            GSRow(symbol: "hand.raised", title: "Permission requests", text: "Always shown on the notch, because the agent waits for your answer.") {
                GSStatus(ok: true, text: "Always on")
            }
            GSDivider()
            GSRow(symbol: "checkmark.circle", title: "Finished tasks", text: "A macOS banner when an agent finishes, if Show system notifications below is on.")
            GSDivider()
            GSToggleRow(symbol: "exclamationmark.triangle", title: "Errors and stuck agents",
                        text: "A red or amber halo and card, plus a macOS notification when macOS allows ZEUS notifications.", isOn: bool("notify.errors"))
            GSDivider()
            GSRow(symbol: "hourglass", title: "Call an agent stuck after", text: "A working agent with no activity for this long turns amber.") {
                GSPopup(selection: SettingsStore.binding("notify.stallMinutes"), options: AgentStall.choices).popupLabel("Call an agent stuck after")
            }
            GSDivider()
            GSToggleRow(symbol: "eye.slash", title: "Stay quiet while sharing or in full screen",
                        text: "Holds back macOS banners for usage, rain and access alerts during a call, on a mirrored display or while a full-screen app is in front.",
                        isOn: Binding(get: { ExtraPreferences.shared.quietWhileSharing }, set: { ExtraPreferences.shared.quietWhileSharing = $0 }))
        }
        GSCard("System notifications") {
            GSRow(symbol: "bell.badge", title: "Show system notifications", text: systemNotifications.permissionNote) {
                HStack(spacing: 10) {
                    Toggle("Show system notifications", isOn: Binding(
                        get: { store.bool("notify.system") },
                        set: { enabled in Task { await systemNotifications.setEnabledFromUserAction(enabled) } }
                    ))
                    .toggleStyle(GSToggleStyle())
                    .labelsHidden()
                    .accessibilityLabel("Show system notifications")
                    if systemNotifications.authorization == .denied {
                        Button("Open Settings") { systemNotifications.openSystemSettingsAfterUserAction() }
                            .buttonStyle(GSButtonStyle())
                    }
                }
            }
        }
        .task { await systemNotifications.refreshAuthorization() }
        GSOtherAppsCards()
    }
}

// MARK: Shortcuts

private struct ShortcutsPage: View {
    var body: some View {
        GSPageHeading(section: .shortcuts, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        GSCard("Summon Zeus") {
            ShortcutRecorderRow(symbol: "mic.fill", title: "Talk to Zeus", text: "",
                                shortcut: Preferences.shared.pushToTalk, defaultValue: .optionCommand) {
                if let new = $0 { Preferences.shared.pushToTalk = new }
            }
            GSDivider()
            ShortcutRecorderRow(symbol: "keyboard", title: "Dictation", text: "",
                                shortcut: DictationSettings.shared.key, defaultValue: .rightCommand, allowsOff: true) {
                DictationSettings.shared.key = $0
            }
        }
        GSCard("Keyboard shortcut") {
            GSRow(symbol: "rectangle.and.hand.point.up.left", title: "Open the agent picker") {
                GSPopup(selection: Binding(get: { ExtraPreferences.shared.openNotch.title },
                                           set: { value in ExtraPreferences.shared.openNotch = ShortcutPreset.allCases.first { $0.title == value } ?? .optionCommandZ }),
                        options: ShortcutPreset.allCases.map(\.title))
            }
        }
        GSCard("Answer from the keyboard") {
            GSToggleRow(symbol: "keyboard", title: "Answer permissions from the keyboard", isOn: bool("shortcut.answerKeys"))
        }
        LearnedShortcutsCard()
    }
}

private struct LearnedShortcutsCard: View {
    @StateObject private var model = LearnedShortcutList()

    var body: some View {
        Group {
            if !model.items.isEmpty {
                GSCard("Learned") {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { GSDivider() }
                        GSRow(symbol: "arrow.uturn.backward", title: item.phrase) {
                            Button("Undo") {
                                _ = LearnedShortcutDisk.shared.remove(item.id)
                                model.reload()
                            }
                            .buttonStyle(GSButtonStyle())
                        }
                    }
                }
            }
        }
        .onAppear { model.reload() }
    }
}

@MainActor
private final class LearnedShortcutList: ObservableObject {
    @Published var items: [LearnedShortcut] = []
    func reload() { items = LearnedShortcutDisk.shared.list() }
}

// MARK: Integrations

private struct IntegrationsPage: View {
    let context: GSContext
    var body: some View {
        GSPageHeading(section: .integrations, subtitle: "Your agents, followed from the notch.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Connections") {
            connection("Claude Code", symbol: "asterisk", agent: .claude)
            GSDivider()
            connection("Codex", symbol: "chevron.left.forwardslash.chevron.right", agent: .codex)
            if let message = context.services.connectMessage {
                GSInfo(text: message)
            }
        }
        GSCard("Available apps") {
            GSToggleRow(symbol: "plus.bubble", title: "Offer Claude Code for new chats", isOn: bool("integrations.offerClaude"))
            GSDivider()
            GSToggleRow(symbol: "plus.bubble", title: "Offer Codex for new chats", isOn: bool("integrations.offerCodex"))
        }
    }

    private func connection(_ name: String, symbol: String, agent: OnboardingFlow.AgentChoice) -> some View {
        let connected = context.services.isConnected(agent)
        return GSRow(symbol: symbol, title: name, text: connected ? "Activity and approvals reach the notch." : "Connection to finish") {
            HStack(spacing: 10) {
                if connected { GSStatus(ok: true, text: "Connected") }
                Button(connected ? "Repair" : "Connect") { context.services.connect(agent) }.buttonStyle(GSButtonStyle(prominent: !connected))
                Button("Check again") { context.refresh() }.buttonStyle(GSButtonStyle())
            }
        }
    }
}

// MARK: Murmure

private struct MurmurePage: View {
    let context: GSContext
    private var settings: DictationSettings { DictationSettings.shared }

    var body: some View {
        GSPageHeading(section: .murmure, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        GSCard("Dictation") {
            GSToggleRow(symbol: "mic", title: "Enable dictation",
                        text: "Write with your voice in the app you are using. Apple Speech and downloaded engines run on this Mac; if you pick a cloud engine below, your audio goes to that provider.",
                        isOn: Binding(get: { settings.enabled }, set: { settings.enabled = $0 }))
            if !(context.services.granted(.microphone) && context.services.granted(.accessibility)) {
                GSInfo(text: "Microphone and Accessibility access are required.")
            }
        }
        SpeechEngineCard(compact: true)
        GSCard("Murmure") {
            ShortcutRecorderRow(symbol: "keyboard", title: "Dictation shortcut", text: "",
                                shortcut: settings.key, defaultValue: .rightCommand, allowsOff: true,
                                otherName: "Talk to Zeus", other: Preferences.shared.pushToTalk) { settings.key = $0 }
            KeyAccessRow()
        }
        GSCard("Language and feedback") {
            GSToggleRow(symbol: "speaker.wave.1", title: "Play dictation sounds", text: "A short cue when recording starts and ends.",
                        isOn: Binding(get: { settings.sounds }, set: { settings.sounds = $0 }))
            GSDivider()
            GSRow(symbol: "globe", title: "Dictation language", text: "Automatic follows macOS for Apple Speech and lets Whisper detect. Selected languages go to Whisper; Parakeet applies a script hint where supported.") {
                GSPopup(selection: Binding(get: { settings.language.title },
                                           set: { value in settings.language = DictationLanguage(persistedValue: value) }),
                        options: DictationLanguage.allCases.map(\.title)).popupLabel("Dictation language")
            }
            GSDivider()
            GSRow(symbol: "doc.on.clipboard", title: "Copy last dictation") {
                Button("Copy") { context.copyLastDictation() }.buttonStyle(GSButtonStyle())
            }
            GSDivider()
            GSRow(symbol: "doc.text", title: "Third-party licenses") {
                Button("Show") { context.showLicenses() }.buttonStyle(GSButtonStyle())
            }
        }
    }
}

// MARK: Voice

private struct VoicePage: View {
    var body: some View {
        GSPageHeading(section: .voice, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        ZeusVoiceCards()
        GSCard("Talk to Zeus") {
            ShortcutRecorderRow(symbol: "bolt", title: "Talk to Zeus", text: "",
                                shortcut: Preferences.shared.pushToTalk, defaultValue: .optionCommand,
                                otherName: "Dictation", other: DictationSettings.shared.key) { if let new = $0 { Preferences.shared.pushToTalk = new } }
            KeyAccessRow()
        }
        WakeWordCard()
        GSCard("Approval keywords") {
            GSToggleRow(symbol: "waveform", title: "Listen for approval keywords",
                        text: "Say a keyword below, such as \u{201C}yes\u{201D} or \u{201C}no\u{201D}, to answer a permission card. This opens the microphone, only while a card is waiting. Off until you turn it on.",
                        isOn: bool("voice.answers"))
            if store.bool("voice.answers"), VoicePermissions.access != .ready {
                GSInfo(text: "Microphone and speech recognition are not allowed yet. Settings \u{203A} Permissions has the buttons.")
            }
        }
        GSCard("Your keywords") {
            words("checkmark.circle", "Approve", "voice.approveWords")
            GSDivider()
            words("xmark.circle", "Deny", "voice.denyWords")
            GSDivider()
            words("arrow.up.forward.app", "Open the app", "voice.openWords")
            Button("Reset the default words") { store.actions["voice.resetWords"]?() }.buttonStyle(GSButtonStyle()).padding(.bottom, 6)
        }
    }

    private func words(_ symbol: String, _ title: String, _ id: String) -> some View {
        GSRow(symbol: symbol, title: title) {
            TextField("comma-separated words", text: Binding(get: { store.string(id) }, set: { store.set(id, $0) }))
                .textFieldStyle(.plain)
                .snapshotSafeText(store.string(id), placeholder: "comma-separated words")
                .font(OB.font(13.5)).foregroundStyle(GS.text)
                .padding(.horizontal, 10).frame(width: 320, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                .accessibilityLabel("\(title) keywords")
        }
    }
}

/// "Listen for “Hey Zeus”": off until turned on; the phrase is heard on this Mac, the request that follows is a normal one.
private struct WakeWordCard: View {
    private var wake: WakeWordController { WakeWordController.shared }

    var body: some View {
        GSCard("Hey Zeus") {
            GSToggleRow(symbol: "ear", title: "Listen for \u{201C}Hey Zeus\u{201D}",
                        text: "Say it, then your request: \u{201C}Hey Zeus, open Spotify.\u{201D} Off until you turn it on. Zeus waits for the phrase on this Mac; nothing is sent while it waits.",
                        isOn: Binding(get: { wake.enabled }, set: { wake.enabled = $0 }))
            if wake.enabled {
                GSDivider()
                GSRow(symbol: wake.listening ? "waveform" : "pause.circle", title: "Status", text: statusNote) {
                    GSStatus(ok: wake.listening, text: wake.listening ? "Listening" : wake.needsPermissions ? (VoicePermissions.access == .needsPrompt ? "Not asked yet" : "Refused") : "Paused")
                }
            }
            GSInfo(text: "Apple\u{2019}s on-device speech recognition, only while someone is talking. It pauses while you hold the talk key, dictate, take a call or lock the Mac. macOS shows the microphone indicator while it listens. What you ask after the phrase is a normal request, as with the talk key: simple commands run on this Mac, and anything else goes to your AI engine (Settings \u{203A} Engine).")
        }
    }

    private var statusNote: String {
        if wake.needsPermissions { return VoicePermissions.statusLine + " Settings \u{203A} Permissions has the buttons." }
        return wake.status
    }
}

// MARK: License

private struct LicensePage: View {
    let navigation: GSNavigation
    private var license: LicenseManager { LicenseManager.shared }

    var body: some View {
        GSPageHeading(section: .license, subtitle: "Make yourself at home.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Your license") {
            GSRow(symbol: "key", title: status, text: license.isLicensed ? "Your license is kept across updates." : "A one-time purchase. Two Macs.") {
                // Partial credential cleanup must keep its explanation and retry visible.
                if license.isLicensed || license.deactivationError != nil {
                    GSDeactivateLicenseControl()
                }
            }
            if !license.isLicensed {
                GSDivider()
                HStack(spacing: 10) {
                    TextField("License key", text: Binding(get: { navigation.licenseKey }, set: { navigation.licenseKey = $0 }))
                        .textFieldStyle(.plain)
                        .snapshotSafeText(navigation.licenseKey, placeholder: "License key")
                        .font(OB.font(13.5)).foregroundStyle(GS.text)
                        .padding(.horizontal, 10).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GS.window))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                        .accessibilityLabel("License key")
                    Button("Activate a license") {
                        let key = navigation.licenseKey
                        Task {
                            navigation.licenseMessage = await license.activate(key)
                            if navigation.licenseMessage == nil { navigation.licenseKey = "" }
                        }
                    }
                    .buttonStyle(GSButtonStyle(prominent: true))
                    .disabled(license.busy || navigation.licenseKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.vertical, 12)
                if let message = navigation.licenseMessage { GSInfo(text: message) }
                GSInfo(text: "One license covers 2 Macs. The key is emailed to you after purchase.")
            }
        }
    }

    private var status: String {
        switch license.status {
        case .licensed(_, let daysLeft?): daysLeft <= 1 ? "Zeus is yours \u{00B7} last day" : "Zeus is yours \u{00B7} \(daysLeft) days left"
        case .licensed: "Zeus is yours."
        case .trial(let days): days <= 1 ? "Trial \u{00B7} last day" : "Trial \u{00B7} \(days) days left"
        case .trialEnded, .expired: "Your free trial has ended."
        case .revoked: "This license was turned off."
        }
    }
}

// MARK: Permissions

private struct PermissionsPage: View {
    let context: GSContext
    var body: some View {
        GSPageHeading(section: .permissions, subtitle: "Each access is optional. Zeus asks only when you turn a feature on.")
            .padding(.bottom, -GS.cardGap)
            .task {
                while !Task.isCancelled {
                    context.refresh()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        GSCard("Access") {
            perm("accessibility", "Accessibility", "Shortcuts, volume, brightness and agents", context.services.granted(.accessibility)) { context.permissions.request(.accessibility) }
            GSDivider()
            perm("location", "Location", "Local weather and rain alerts", context.services.locationAllowed) { context.services.allowLocation() }
            GSDivider()
            perm("calendar", "Calendar", "Events and video calls", context.services.granted(.calendar)) { context.permissions.request(.calendar) }
            GSDivider()
            perm("checklist", "Reminders", "Read, create and complete tasks", context.services.granted(.reminders)) { context.permissions.request(.reminders) }
            GSDivider()
            perm("bell.badge", "Notifications", "Zeus alerts in macOS", context.services.notificationsAllowed) { context.services.allowNotifications() }
            GSDivider()
            perm("internaldrive", "Full Disk Access", "Notifications coming from other apps", context.services.fullDiskAccess) { context.services.allowFullDiskAccess() }
            GSDivider()
            voicePerm("mic", "Microphone", "Hey Zeus, the talk key and dictation", VoicePermissions.mic, .microphone)
            GSDivider()
            voicePerm("waveform", "Speech recognition", "Turns what you say into words on this Mac", VoicePermissions.speech, .speech)
            GSDivider()
            capturePerm("camera", "Camera", "Records you while you read in the teleprompter", context.permissions.cameraPermissionState, .camera) {
                context.permissions.request(.camera)
            }
            GSDivider()
            capturePerm("rectangle.dashed.badge.record", "Screen Recording", "Screenshots during a turn and system audio for Waves", context.permissions.screenPermissionState, .screen) {
                context.permissions.request(.screen)
            }
            GSDivider()
            GSRow(symbol: "keyboard", title: "Keys from other apps", text: "Lets Zeus see the talk and dictation shortcuts. Accessibility or Input Monitoring is enough.") {
                HStack(spacing: 10) {
                    GSStatus(ok: KeyListenAccess.granted, text: KeyListenAccess.granted ? (KeyListenAccess.accessibility ? "Accessibility" : "Input Monitoring") : "Not allowed")
                    if !KeyListenAccess.granted {
                        Button("Allow Input Monitoring") { KeyListenAccess.requestInputMonitoring() }.buttonStyle(GSButtonStyle())
                    }
                }
            }
            GSDivider()
            GSRow(symbol: "music.note", title: "Automation",
                  text: context.permissions.automationMessage
                    ?? "Control playback in Music and Spotify, and read slide notes in Keynote and PowerPoint. macOS asks about each app only while it is open.") {
                if context.permissions.automationAsking {
                    GSStatus(ok: false, text: "Waiting for macOS…")
                } else if context.permissions.automationPending && !context.services.granted(.automation) {
                    GSStatus(ok: false, text: "Checking…")
                } else if context.services.granted(.automation) {
                    HStack(spacing: 10) {
                        GSStatus(ok: true, text: automationStatus)
                        // Access is per app: another one can be added while it is open.
                        if Automation.allowedTargets.count < Automation.players.count {
                            Button("Allow more") { context.permissions.request(.automation) }.buttonStyle(GSButtonStyle())
                                .accessibilityLabel("Allow Automation for another app")
                        }
                    }
                } else {
                    Button("Allow") { context.permissions.request(.automation) }.buttonStyle(GSButtonStyle())
                        .accessibilityLabel("Allow Automation")
                }
            }
        }
        GSTrustedChatsCard()
    }

    /// "Allowed: Music, Spotify": the apps macOS lets Zeus script (access is per app, so it can be partial).
    private var automationStatus: String {
        let names = Automation.allowedTargets.map(Automation.name)
        return names.isEmpty ? "Allowed" : "Allowed: " + names.joined(separator: ", ")
    }

    /// Allowed / Not asked yet (Allow raises macOS's one prompt) / Refused (Allow opens the pane).
    private func voicePerm(_ symbol: String, _ title: String, _ text: String, _ state: PermissionState, _ kind: PermissionsModel.Kind) -> some View {
        GSRow(symbol: symbol, title: title, text: state == .denied ? "Refused. Turn it on in System Settings \u{203A} Privacy \u{203A} \(title)." : text) {
            switch state {
            case .authorized: GSStatus(ok: true, text: "Allowed")
            case .notDetermined:
                Button("Allow") { Task { await VoicePermissions.ensure(explicit: true); context.refresh() } }.buttonStyle(GSButtonStyle(prominent: true))
                    .accessibilityLabel("Allow \(title)")
            case .denied:
                HStack(spacing: 10) {
                    GSStatus(ok: false, text: "Refused")
                    Button("Open Settings") { context.permissions.open(kind) }.buttonStyle(GSButtonStyle()).accessibilityLabel("Open \(title) settings")
                }
            }
        }
    }

    /// Camera and Screen Recording: request-only (never starts capture).
    private func capturePerm(_ symbol: String, _ title: String, _ text: String, _ state: PermissionState, _ kind: PermissionsModel.Kind, allow: @escaping () -> Void) -> some View {
        GSRow(symbol: symbol, title: title, text: state == .denied ? "Refused. Turn it on in System Settings \u{203A} Privacy \u{203A} \(title)." : text) {
            switch state {
            case .authorized: GSStatus(ok: true, text: "Allowed")
            case .notDetermined:
                Button("Allow", action: allow).buttonStyle(GSButtonStyle(prominent: true)).accessibilityLabel("Allow \(title)")
            case .denied:
                HStack(spacing: 10) {
                    GSStatus(ok: false, text: "Refused")
                    Button("Open Settings") { context.permissions.open(kind) }.buttonStyle(GSButtonStyle()).accessibilityLabel("Open \(title) settings")
                }
            }
        }
    }

    private func perm(_ symbol: String, _ title: String, _ text: String, _ granted: Bool, _ allow: @escaping () -> Void) -> some View {
        GSRow(symbol: symbol, title: title, text: text) {
            if granted { GSStatus(ok: true, text: "Allowed") } else {
                Button("Allow", action: allow).buttonStyle(GSButtonStyle()).accessibilityLabel("Allow \(title)")
            }
        }
    }
}

// MARK: Privacy

private struct PrivacyPage: View {
    let context: GSContext
    @AppStorage(DriveAutonomy.settingsKey) private var driveAutonomy = DriveAutonomy.default.rawValue
    @AppStorage(CLIAccess.defaultsKey) private var cliSensitive = false

    /// The pop-up shows titles; the setting stores the raw value.
    private var autonomyTitle: Binding<String> {
        Binding(get: { (DriveAutonomy(rawValue: driveAutonomy) ?? .default).title },
                set: { title in driveAutonomy = (DriveAutonomy.allCases.first { $0.title == title } ?? .default).rawValue })
    }

    var body: some View {
        GSPageHeading(section: .privacy, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        GSCard("Notification details") {
            GSToggleRow(symbol: "eye", title: "Show project and command details",
                        text: "Turn off to hide commands and project names on cards and banners. Meeting mode hides them too.", isOn: bool("privacy.details"))
        }
        GSCard("Music") {
            GSToggleRow(symbol: "text.quote", title: "Synced lyrics",
                        text: "Sends the song title, artist, album and length to lrclib.net to fetch time-synced lyrics, which are kept on this Mac. Off until you turn it on.",
                        isOn: bool("privacy.lyrics"))
        }
        GSCard("Control from the notch") {
            GSRow(symbol: "accessibility", title: "Accessibility", text: "") {
                Button("Open Accessibility settings") { store.actions["privacy.openAccessibility"]?() }.buttonStyle(GSButtonStyle())
            }
            GSDivider()
            GSRow(symbol: "cursorarrow.motionlines", title: "When Zeus may drive your Mac",
                  text: (DriveAutonomy(rawValue: driveAutonomy) ?? .default).explanation) {
                GSPopup(selection: autonomyTitle, options: DriveAutonomy.allCases.map(\.title)).popupLabel("When Zeus may drive your Mac")
            }
        }
        GSCard("Command line") {
            GSToggleRow(symbol: "terminal", title: "Allow command-line control of sensitive actions",
                        text: "Lets the zeus command (and any program on this Mac running as you) listen on the microphone, record, type or click for you, open coding agents, terminals and browsers, and import keys. Off by default; read-only commands such as status always work.",
                        isOn: $cliSensitive)
        }
    }
}

// MARK: Diagnostics

private struct DiagnosticsPage: View {
    let context: GSContext
    var body: some View {
        GSPageHeading(section: .diagnostics, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        GSCard("Local connection") {
            let agents = SettingStatus.value("diag.agents")
            GSRow(symbol: "point.3.connected.trianglepath.dotted", title: "Agents", text: agents.0 ? agents.1 : "") {
                let up = context.connectionUp()
                GSStatus(ok: up, text: up ? "Connected" : "Offline")
            }
        }
        DiagnosticsLogsCard()
        GSCard("Restart the local connection") {
            GSRow(symbol: "arrow.clockwise", title: "Restart the daemon", text: "Running tasks stay in their own applications.") {
                Button("Restart") { context.restartConnection() }.buttonStyle(GSButtonStyle())
            }
        }
    }
}

/// System Audio Recording: its status, and "Allow" (the only place besides the toggle and the Waves tab that may ask).
private struct SpectrumPermissionRow: View {
    private var service: AudioSpectrumService { .shared }
    var body: some View {
        GSRow(symbol: "speaker.wave.2", title: "System audio",
              text: service.permission == .refused ? "Refused. Turn it on in System Settings \u{203A} Privacy & Security \u{203A} Screen & System Audio Recording." : "Zeus never records or saves the sound; it only measures how loud each pitch is.") {
            switch service.permission {
            case .allowed: GSStatus(ok: true, text: "Allowed")
            case .notAsked:
                Button("Allow") { service.allowPressed() }.buttonStyle(GSButtonStyle(prominent: true)).accessibilityLabel("Allow system audio")
            case .refused:
                HStack(spacing: 10) {
                    GSStatus(ok: false, text: "Refused")
                    Button("Open Settings") { service.openSystemSettings() }.buttonStyle(GSButtonStyle()).accessibilityLabel("Open system audio settings")
                }
            }
        }
    }
}

/// A small drawing of the running card in each theme, for the picture choices.
private struct RunningCardMini: View {
    let essentials: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Circle().fill(Theme.glow).frame(width: 7, height: 7)
                    Text("Claude Code").font(.system(size: 8, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Text("Working").font(.system(size: 7)).foregroundStyle(.white.opacity(0.5))
                }
                if !essentials {
                    HStack(alignment: .bottom, spacing: 2.5) {
                        ForEach(0..<22, id: \.self) { i in
                            Capsule().fill(Theme.glow.opacity(0.8)).frame(width: 3, height: CGFloat(6 + (i * 7) % 17))
                        }
                    }
                    .frame(height: 24, alignment: .bottom)
                }
                Text("Editing the settings page").font(.system(size: 7)).foregroundStyle(.white.opacity(0.55))
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AirDropPermissionRow: View {
    private var status: FolderAccess.Status { FolderAccess.status(for: .downloads) }

    var body: some View {
        GSRow(symbol: "airdrop", title: "Glow when AirDrop arrives",
              text: status == .denied ? "Downloads folder access is off. Turn on Zeus in System Settings \u{203A} Privacy & Security \u{203A} Files and Folders." : "Blue intake glow and drops the file on the shelf.") {
            HStack(spacing: 8) {
                if status == .granted {
                    Toggle("Glow when AirDrop arrives", isOn: Binding(
                        get: { SettingsStore.shared.bool("lights.airDrop") },
                        set: { SettingsStore.shared.set("lights.airDrop", $0 ? "true" : "false") }
                    ))
                    .toggleStyle(GSToggleStyle())
                    .labelsHidden()
                } else if status == .notDetermined {
                    Button("Allow") {
                        if FolderAccess.request(for: .downloads) == .granted {
                            SettingsStore.shared.set("lights.airDrop", "true")
                        }
                    }
                    .buttonStyle(GSButtonStyle(prominent: true))
                } else {
                    Button("Open Settings") {
                        FolderAccess.openSettings()
                    }
                    .buttonStyle(GSButtonStyle())
                }
            }
        }
    }
}

private struct ScreenshotPermissionRow: View {
    private var status: FolderAccess.Status { FolderAccess.status(for: .desktop) }

    var body: some View {
        GSRow(symbol: "camera", title: "Screenshot cue",
              text: status == .denied ? "Desktop folder access is off. Turn on Zeus in System Settings \u{203A} Privacy & Security \u{203A} Files and Folders." : "Camera cue and shelf drop for new screenshots.") {
            HStack(spacing: 8) {
                if status == .granted {
                    Toggle("Screenshot cue", isOn: Binding(
                        get: { SettingsStore.shared.bool("lights.screenshot") },
                        set: { SettingsStore.shared.set("lights.screenshot", $0 ? "true" : "false") }
                    ))
                    .toggleStyle(GSToggleStyle())
                    .labelsHidden()
                } else if status == .notDetermined {
                    Button("Allow") {
                        if FolderAccess.request(for: .desktop) == .granted {
                            SettingsStore.shared.set("lights.screenshot", "true")
                        }
                    }
                    .buttonStyle(GSButtonStyle(prominent: true))
                } else {
                    Button("Open Settings") {
                        FolderAccess.openSettings()
                    }
                    .buttonStyle(GSButtonStyle())
                }
            }
        }
    }
}
