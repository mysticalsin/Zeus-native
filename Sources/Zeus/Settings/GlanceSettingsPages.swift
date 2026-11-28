import AppKit
import Observation
import SwiftUI
import ZeusCore

/// The Day to day card speaks which of its six switches are on. It does not change them.
enum DayToDayVoice {
    static var speakDay: () -> Void = {}
}

/// The Agent notifications card speaks errors, the stall, and quiet while sharing. It does not ask macOS.
enum NotifySetupVoice {
    static var speakNotices: () -> Void = {}
}

/// The Weather card speaks the city and the units. It does not fetch a forecast.
enum WeatherPlaceVoice {
    static var speakPlace: () -> Void = {}
}

/// The Home style and Physical finish rows speak the frame. They do not change the card pictures.
enum HomeFrameVoice {
    static var speakFrame: () -> Void = {}
}

/// The Screen card speaks the bottom-corner rounding and the size. It does not move a window.
enum ScreenCornerVoice {
    static var speakCorners: () -> Void = {}
}

/// The Card details card speaks auto-hide and the close delay. It does not close the notch.
enum NotchCloseVoice {
    static var speakClose: () -> Void = {}
}

/// The Everyday actions rows speak which lights are on. They do not change them.
enum EverydayLightsVoice {
    static var speakLights: () -> Void = {}
}

/// The halo arm and island rows speak those two choices. They do not change the light picture.
enum HaloArmVoice {
    static var speakArm: () -> Void = {}
}

/// The Music rows speak the four music lights. They do not start playback.
enum MusicLightsVoice {
    static var speakLights: () -> Void = {}
    /// The live music-wave switch. A missing key is on, the same as the notch.
    static var wingsOn: () -> Bool = {
        UserDefaults.standard.object(forKey: "topBar.musicWings") as? Bool ?? true
    }
}

/// The Running card speaks the look, how the notch opens, and the hover delay. It does not open the notch.
enum RunningCardVoice {
    static var speakCard: () -> Void = {}
}

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
    /// "Allow all" on the Permissions page; nil in parity captures, which then show the rows only.
    @ObservationIgnored var sweep: PermissionSweepRunner?
    /// The drawn notch's model. Nil until the app sets it, and then the Appearance card is not placed.
    @ObservationIgnored var drawnNotch: (any DrawnNotchControlling)?
    /// The per-app equaliser behind the Sounds card. The app delegate builds it; Settings only asks it.
    @ObservationIgnored var equaliser: () -> (any EqualiserControlling)? = { nil }

    init(services: OnboardingServices) {
        self.services = services
    }

    func refresh() {
        services.refresh()
        LicenseManager.shared.refresh()
        SettingsStore.shared.refreshLaunchAtLogin()
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
            case .general: GeneralPage(navigation: navigation, openGuide: context.openGuide)
            case .appearance: AppearancePage(context: context, navigation: navigation)
            case .sounds: SoundsPage(context: context)
            case .notifications: GSNotificationsPage()
            case .shortcuts: ShortcutsPage()
            case .insomnia: InsomniaSettingsPage()
            case .integrations: AIConnectionsPage(context: context)
            case .murmure: MurmurePage(context: context, navigation: navigation)
            case .polyglot: PolyglotSettingsPage(navigation: navigation)
            case .dictation: DictationSettingsPage(context: context, navigation: navigation)
            case .voice: VoicePage(navigation: navigation)
            case .engine: EnginePage()
            case .iPhone: IPhonePage()
            case .features: FeaturesSettingsPage()
            case .beamer: BeamerSettingsPage(context: context)
            case .tiling: TilingSettingsPage()
            case .shelf: ShelfSettingsPage()
            case .license: LicensePage(navigation: navigation)
            case .permissions: PermissionsPage(context: context)
            case .privacy: PrivacyPage(context: context)
            case .diagnostics: DiagnosticsPage(context: context)
            case .about: AboutPage(navigation: navigation)
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
    let openGuide: () -> Void
    var body: some View {
        GSPageHeading(section: .general, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        // Window appearance and Language are not rows: the windows are drawn dark only and Zeus speaks English only.
        GSCard("Your defaults") {
            GSRow(symbol: "display.2", title: "Show the notch on") {
                HStack(spacing: 8) {
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say where the notch is") { NotchController.speakNotch() }
                    GSPopup(selection: SettingsStore.binding("notch.displays"), options: NotchDisplayMode.allCases.map(\.rawValue)).popupLabel("Show the notch on")
                }
            }
            GSDivider()
            GSRow(symbol: "bubble.left.and.bubble.right", title: "Default agent", text: "For new conversations opened from the notch.") {
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the default agent") { DefaultAgentVoice.speakAgent() }
            }
            HStack(spacing: 12) {
                agentChoice("Codex")
                agentChoice("Claude Code")
            }
            .padding(.bottom, 8)
        }
        GSCard("Day to day") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say what's on day to day") { DayToDayVoice.speakDay() }
            }
            GSToggleRow(symbol: "power", title: "Launch Zeus at login", text: "Ready as soon as you sign in to your Mac.", isOn: bool("general.launchAtLogin"))
            GSDivider()
            GSToggleRow(symbol: "cup.and.saucer", title: "Keep the Mac from sleeping", text: "Agents keep working while the screen can still lock.", detail: "Your screen can still turn off and lock.", isOn: bool("general.keepAwake"))
            GSDivider()
            GSToggleRow(symbol: "music.note", title: "Keep the display awake while music plays", text: "Holds the display on only while the notch source is playing.", detail: "Stops on low battery or heat.", isOn: bool("keepAwake.whileMusic"))
            GSDivider()
            GSToggleRow(symbol: "person.2.wave.2", title: "Meeting mode", text: "Quiet sounds and private previews during calls and screen sharing.", isOn: bool("general.meetingMode"))
            GSDivider()
            GSToggleRow(symbol: "shared.with.you", title: "Show in screen sharing", text: "Off keeps Zeus windows out of screen shares and recordings.", isOn: bool("general.showInScreenSharing"))
            GSDivider()
            GSToggleRow(symbol: "hand.wave", title: "Welcome back recap", text: "After 10 minutes away, the notch shows what your agents finished.", detail: "It also shows what they are waiting on.", isOn: bool("general.welcomeBack"))
        }
        GSSetupCard(openGuide: openGuide)
        GSCard("Keep awake") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how keep awake is set") { KeepAwakeSession.speakSetup() }
            }
            GSRow(symbol: "timer", title: "Session length", text: "How long the cup on Home keeps the Mac awake.") {
                GSPopup(selection: Binding(
                    get: { KeepAwakeLength.label(keepAwake.homeMinutes) },
                    set: { if let minutes = KeepAwakeLength.minutes(fromLabel: $0) { keepAwake.homeMinutes = minutes } }
                ), options: KeepAwakeLength.all.map(KeepAwakeLength.label)).popupLabel("Keep awake session length")
            }
            GSDivider()
            GSRow(symbol: "battery.25percent", title: "Battery floor", text: "Ends a session below this charge on battery.", detail: "A notice comes first at 20%.") {
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
            GSLinkRow(symbol: "moon.zzz", title: "Lid-closed mode", text: "Keep agents working with the lid shut.", destination: .insomnia, navigation: navigation)
        }
    }

    private var keepAwake: KeepAwakeSession { .shared }

    private func agentChoice(_ name: String) -> some View {
        let selected = SettingsStore.binding("general.defaultAgent").wrappedValue == name || (name == "Codex" && store.string("general.defaultAgent").isEmpty)
        return Button { store.set("general.defaultAgent", name) } label: {
            HStack(spacing: 14) {
                EngineBrandLogo(agentLabel: name, size: 18, tint: .white)
                    .accessibilityHidden(true)
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

/// The production Setup card is independent of Settings' live stores and services.
struct GSSetupCard: View {
    let openGuide: () -> Void

    var body: some View {
        GSCard("Setup") {
            GSRow(symbol: "sparkles", title: "Show setup guide", text: "Open the guide again, even if you closed it earlier.", detail: "Revisit agents and permissions.") {
                Button("Open guide", action: openGuide)
                    .buttonStyle(GSButtonStyle())
                    .ownedJourneyControl("settings.general.openGuide")
            }
        }
    }
}

// MARK: Appearance

private struct AppearancePage: View {
    let context: GSContext
    let navigation: GSNavigation

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
            HStack(spacing: 8) {
                GSInfo(text: "Changes apply instantly.")
                Spacer(minLength: 8)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the card style") { CardFinish.speakLook() }
            }
            GSDivider()
            GSRow(symbol: "circle.lefthalf.filled", title: "Dark Mode", text: "Whether the Mac is using Dark Mode.") {
                Button("Say it") { context.topBar?.speakDarkMode() }
                    .buttonStyle(GSButtonStyle())
                    .disabled(context.topBar == nil)
            }
            GSDivider()
            GSRow(symbol: "rectangle.3.group", title: "Home style", text: "The frame of the Home band: cards, no frame, or no frame with colour.") {
                HStack(spacing: 8) {
                    GSPopup(selection: SettingsStore.binding("appearance.homeStyle"), options: SettingsCatalog.option("appearance.homeStyle")?.choices ?? []).popupLabel("Home style")
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the Home frame") { HomeFrameVoice.speakFrame() }
                }
            }
            GSDivider()
            GSRow(symbol: "square.stack.3d.up", title: "Customize Physical", text: "In the Physical theme, give Home its own finish instead of the card finish.") {
                GSPopup(selection: physicalFinishBinding, options: SettingsCatalog.option("appearance.physicalFinish")?.choices ?? []).popupLabel("Physical finish")
            }
        }
        GSCard("Top bar") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the closed notch is set") { NotchFitVoice.speakFit() }
            }
            GSRow(symbol: "arrow.up.and.down", title: "Top bar position",
                  text: "Lowers the closed notch with its light, ticker and wings.", detail: "The open panel and the screen edge light stay at the top, on every display.") {
                HStack(spacing: 10) {
                    Text("Higher").font(GS.rowText).foregroundStyle(GS.secondary)
                    OBTickSlider(value: Binding(get: { TopBarPositionModel.shared.offset }, set: { TopBarPositionModel.shared.choose($0) }),
                                 range: TopBarPosition.minimum...TopBarPosition.maximum, step: TopBarPosition.step)
                        .frame(width: 200).environment(\.ob, OB.Palette.settings).accessibilityLabel("Top bar position")
                        .accessibilityIdentifier("settings.appearance.topBarPosition")
                    Text("Lower").font(GS.rowText).foregroundStyle(GS.secondary)
                    Text("\(Int(TopBarPositionModel.shared.offset)) pt").font(GS.rowText).foregroundStyle(GS.secondary).monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            GSDivider()
            GSRow(symbol: "arrow.counterclockwise", title: "Reset position", text: "Back to flush with the top of the screen.") {
                Button("Reset") { TopBarPositionModel.shared.reset() }
                    .buttonStyle(GSButtonStyle())
                    .ownedJourneyControl("settings.appearance.topBarPositionReset")
            }
            GSDivider()
            GSToggleRow(symbol: store.bool(ZeusScreenSharePolicy.showInSharingKey) ? "eye" : "eye.slash",
                        title: "Show Zeus in screen shares",
                        text: "People sharing your screen can see Zeus when this is on.", detail: "Off keeps Zeus out of screen sharing and screenshots, including during meetings.",
                        isOn: bool(ZeusScreenSharePolicy.showInSharingKey))
        }
        if let drawnNotchCard = DrawnNotchCardModel(context: context, navigation: navigation) { DrawnNotchCard(model: drawnNotchCard) }
        GSCard("Running card") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the running card is set") { RunningCardVoice.speakCard() }
            }
            HStack(spacing: 12) {
                runningTheme("Wave", "")
                runningTheme("Essentials", "")
            }
            GSDivider()
            GSRow(symbol: "cursorarrow.click", title: "Open the notch on", text: "Hover opens the notch after the delay.", detail: "Click opens it only when you click the notch.") {
                HStack(spacing: 8) {
                    GSPopup(selection: SettingsStore.binding("notch.openTrigger"), options: SettingsCatalog.option("notch.openTrigger")?.choices ?? []).popupLabel("Open the notch on")
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the notch opens") { NotchController.speakOpen() }
                }
            }
            GSDivider()
            // The delay only applies to hover, so it is subdued while the trigger is Click.
            let clickTrigger = SettingsStore.shared.string("notch.openTrigger") == "Click"
            GSRow(symbol: "hand.point.up.left", title: "Hover delay", text: "How long the pointer rests before the notch opens.", detail: "Used when the notch opens on hover.") {
                GSPopup(selection: SettingsStore.binding("notch.openDelay"), options: SettingsCatalog.option("notch.openDelay")?.choices ?? []).popupLabel("Hover delay")
            }
            .disabled(clickTrigger)
            .opacity(clickTrigger ? 0.5 : 1)
        }
        HomeAppearanceCard()
        GSCard("Card details and behavior") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the notch closes") { NotchCloseVoice.speakClose() }
            }
            GSToggleRow(symbol: "rectangle.topthird.inset.filled", title: "Hide the notch automatically", text: "Closes when you move the pointer away.", isOn: bool("notch.autoHide"))
            GSDivider()
            GSRow(symbol: "timer", title: "Delay before closing") {
                GSPopup(selection: SettingsStore.binding("notch.closeDelay"), options: SettingsCatalog.option("notch.closeDelay")?.choices ?? []).popupLabel("Delay before closing")
            }
        }
        GSCard("Zeus beside the pointer") {
            GSRow(symbol: "cursorarrow.rays", title: "Show Zeus beside the pointer",
                  text: "He stays out of the way until you call him, then fades out.", detail: "He appears for a talk shortcut, a voice turn or when he points, then fades after about 2 seconds.") {
                HStack(spacing: 8) {
                    GSPopup(selection: Binding(get: { BuddyPreference.shared.show.title },
                                               set: { value in BuddyPreference.shared.show = BuddyShow.allCases.first { $0.title == value } ?? .onCall }),
                            options: BuddyShow.allCases.map(\.title)).popupLabel("Show Zeus beside the pointer")
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say when Zeus appears") { BuddyPreference.speakShow() }
                }
            }
            GSInfo(text: "The More button (three dots) on the notch has the same choice for a quick change.")
            GSDivider()
            GSRow(symbol: "circle.circle", title: "Persona and mascot",
                  text: "Classic keeps this mascot; Orb stays off until you choose it.") {
                GSPopup(selection: Binding(get: { PersonaSetting.shared.displayName },
                                           set: { PersonaSetting.shared.select(displayName: $0) }),
                        options: PersonaSetting.choices, label: "Persona and mascot")
            }
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
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the notch light") { HaloStyle.speakLight() }
            }
            GSRow(symbol: "sparkles", title: "Entrance animation") {
                HStack(spacing: 8) {
                    GSPopup(selection: HaloChoices.entranceTitle, options: HaloChoices.entrances).popupLabel("Entrance animation")
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the halo entrance") { HaloEntranceVoice.speakEntrance() }
                }
            }
            GSDivider()
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the halo is measured") { HaloMeasureVoice.speakMeasure() }
            }
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
                HStack(spacing: 8) {
                    GSPopup(selection: SettingsStore.binding("halo.armWidth"), options: HaloChoices.armWidths).popupLabel("Halo arm width")
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the halo arm") { HaloArmVoice.speakArm() }
                }
            }
            GSDivider()
            GSRow(symbol: "rectangle.dashed", title: "Island background",
                  text: "Draws only the mascot and the text, with no body or glow.", detail: "The notch and the open panel stay black.") {
                GSPopup(selection: SettingsStore.binding(NotchBackground.settingID), options: NotchBackground.allCases.map(\.rawValue)).popupLabel("Island background")
            }
            GSDivider()
            GSRow(symbol: "line.3.horizontal", title: "Light thickness") {
                OBTickSlider(value: Binding(get: { max(100, store.double("halo.thickness")) }, set: { store.set("halo.thickness", String(Int($0))) }), range: 100...200, step: 5)
                    .frame(width: 260).environment(\.ob, OB.Palette.settings).accessibilityLabel("Light thickness")
            }
            GSDivider()
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the halo meets the screen") { HaloWashVoice.speakWash() }
            }
            GSToggleRow(symbol: "dot.radiowaves.left.and.right", title: "Light wave to the screen edges", text: "A wave of light leaves the notch when an agent starts or finishes.", detail: "The wave ripples across the screen and fades.", isOn: bool("halo.edgeWave"))
        }
        GSCard("Small moments, softly signaled") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say which everyday lights are on") { EverydayLightsVoice.speakLights() }
            }
            Text("Keep the visual feedback you find useful.").font(GS.rowText).foregroundStyle(GS.secondary).padding(.bottom, 4)
            Text("Everyday actions").font(OB.font(13, .semibold)).foregroundStyle(GS.secondary).padding(.top, 8)
            light("lights.battery", "battery.100.bolt", "Green gauge when plugged in", "Shows the battery level when power changes.")
            light("lights.rain", "cloud.rain", "Incoming rain alert", "A heads-up before the rain arrives.")
            light("lights.timer", "timer", "Timer light gauge", "A quiet countdown around the notch.")
            light("lights.micGlow", "mic", "Purple glow while the mic listens", "Follows your voice during a spoken reply.")
            light("lights.reminderGlow", "checklist", "Glow when a reminder is added", nil)
            light("lights.copy", "doc.on.doc", "Light sweep on copy", "A white sweep confirms a copy.")
            light("lights.shelf", "tray.and.arrow.down", "Intake light when files land", "A brief glow for Shelf drops.")
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the arrival lights are set") { ArrivalLightsVoice.speakLights() }
            }
            AirDropPermissionRow()
            GSDivider()
            ScreenshotPermissionRow()
            GSDivider()
            light("lights.capsLock", "capslock", "Case-key lights (Caps Lock and Shift)", "Shows Caps Lock changes and Shift held on its own.", last: true)
            HStack {
                Text("Music").font(OB.font(13, .semibold)).foregroundStyle(GS.secondary)
                Spacer(minLength: 8)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say which music lights are on") { MusicLightsVoice.speakLights() }
            }
            .padding(.top, 14)
            GSToggleRow(symbol: "waveform", title: "Light wave while music plays", text: "A soft wave in the artwork\u{2019}s colors beside the notch while a track plays.", isOn: musicWingsBinding)
            GSDivider()
            light("lights.musicProgress", "circle.dashed", "Progress outline on the music preview", "The outline follows the track\u{2019}s progress.")
            light("lyrics.wordByWord", "music.note.list", "Light lyrics word by word", "Each word lights as it is sung. Word timing is estimated from the line timing.")
            light("lights.liveSpectrum", "waveform.path", "React to real sound", "The music wave follows the sound your Mac is playing. Zeus asks for System Audio Recording once, when you turn this on, and listens only while music plays.", last: true)
            GSDivider()
            GSRow(symbol: "chart.bar.fill", title: "Waves style", text: "How the Waves tab draws the spectrum.", detail: "Add the tab under Top bar tabs, further down this page.") {
                HStack(spacing: 8) {
                    GSPopup(selection: SettingsStore.binding("waves.style"), options: WaveStyle.allCases.map(\.rawValue)).popupLabel("Waves style")
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the waves are set") { WavesSetupVoice.speakWaves() }
                }
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
            screenCard
            musicSourceCard
            TopBarTabsCard(context: context)
        }
    }

    private var screenCard: some View {
        GSCard("Screen") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the screen corners are set") { ScreenCornerVoice.speakCorners() }
            }
            GSToggleRow(symbol: "rectangle.roundedbottom", title: "Round the bottom screen corners",
                        text: "Rounds the bottom corners of a notched display to match the top.", detail: "The rounded corners are click-through.",
                        isOn: bool("screen.roundBottomCorners"))
            GSDivider()
            GSRow(symbol: "circle.bottomhalf.filled", title: "Corner size") {
                GSPopup(selection: SettingsStore.binding("screen.cornerRadius"), options: SettingsCatalog.option("screen.cornerRadius")?.choices ?? []).popupLabel("Corner size")
            }
        }
    }

    private var musicSourceCard: some View {
        GSCard("Music source") {
            GSRow(symbol: "music.note.list", title: "Show music from") {
                HStack(spacing: 8) {
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say which player the notch shows") { NowPlayingHub.speakSource() }
                    GSPopup(selection: SettingsStore.binding(NowPlayingHub.followSettingID),
                            options: SettingsCatalog.option(NowPlayingHub.followSettingID)?.choices ?? []).popupLabel("Show music from")
                }
            }
        }
    }

    private var hudCard: some View {
        GSCard("Volume, brightness and keys") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say which notch lights are on") { SystemHUDSettings.speakLights() }
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say which other notch lights are on") { HudExtraVoice.speakExtras() }
            }
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

/// The world clock and countdown speak the city choice, whether a title is set, and the day. The words stay unspoken.
enum HomeLaterVoice {
    static var speakLater: () -> Void = {}
}

/// The Home backdrop speaks the drawing and whether it moves. It does not change the backdrop.
enum HomeBackdropVoice {
    static var speakBackdrop: () -> Void = {}
}

/// Home: which widget each of the four cards shows, its style, the backdrop. The same choices as Customize Home on the notch.
private struct HomeAppearanceCard: View {
    private let symbols = ["1.square", "2.square", "3.square", "4.square"]

    var body: some View {
        GSCard("Home") {
            HStack(alignment: .top, spacing: 8) {
                Text("Choose what the four Home cards show. Long-press Home or open the More menu (three dots) to change them right on the notch.")
                    .font(GS.rowText).foregroundStyle(GS.secondary)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the Home cards") { HomeSlots.speakHome() }
            }
            .padding(.bottom, 8)
            ForEach(1...4, id: \.self) { slot in
                GSRow(symbol: symbols[slot - 1], title: "Card \(slot)") {
                    GSPopup(selection: SettingsStore.binding(HomeSlots.settingID(slot: slot)), options: SettingsCatalog.option(HomeSlots.settingIDs[slot - 1])?.choices ?? [])
                }
                GSDivider()
            }
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the Home styles") { HomeSlots.speakStyles() }
            }
            style("clock", "Clock style", "home.variant.clock")
            GSDivider()
            style("music.note", "Music style", "home.variant.music")
            GSDivider()
            style("cloud.sun", "Weather style", "home.variant.weather")
            GSDivider()
            style("calendar", "Calendar style", "home.variant.calendar")
            GSDivider()
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how the world clock and countdown are set") { HomeLaterVoice.speakLater() }
            }
            GSRow(symbol: "globe", title: "World clock cities", text: "Time zone names, like Europe/London.") {
                GSTextInput(text: SettingsStore.binding("home.worldClock.zones"), placeholder: "Europe/London, Asia/Tokyo", label: "World clock cities")
            }
            GSDivider()
            GSRow(symbol: "hourglass", title: "Countdown title") {
                GSTextInput(text: SettingsStore.binding("home.countdown.title"), placeholder: "Launch day", label: "Countdown title")
            }
            GSDivider()
            GSRow(symbol: "calendar.badge.clock", title: "Countdown date", text: "Type the day as year-month-day, for example 2026-12-25.") {
                GSTextInput(text: SettingsStore.binding("home.countdown.date"), placeholder: "2026-12-25", label: "Countdown date")
            }
        }
        GSCard("Home backdrop") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the Home backdrop") { HomeBackdropVoice.speakBackdrop() }
            }
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
                HStack(alignment: .top, spacing: 8) {
                    Text("Choose which pages the open notch shows and in what order. Home always comes first.")
                        .font(GS.rowText).foregroundStyle(GS.secondary)
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say which tabs are on") { TopBarLayout.speakTabs() }
                }
                .padding(.bottom, 4)
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
                if full { GSInfo(text: "The row holds \(GlanceTopBar.maxTabs) tabs.") }
            }
            GSCard("Weather") {
                HStack {
                    Spacer(minLength: 0)
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say where the forecast is from") { WeatherPlaceVoice.speakPlace() }
                }
                GSRow(symbol: "location.magnifyingglass", title: "City", text: "Only the city name is sent.", detail: "Forecasts come from Open-Meteo. Press Return to apply the city.") {
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
    let context: GSContext
    var body: some View {
        GSPageHeading(section: .sounds, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        GSCard("Sound feedback") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how sound feedback is set") { FeedbackSetupVoice.speakFeedback() }
            }
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
        LockWakeChimesCard()
            .disabled(!ExtraPreferences.shared.soundsOn)
            .opacity(ExtraPreferences.shared.soundsOn ? 1 : 0.5)
        GSCard("Your cues") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the cue sounds") { SoundCatalog.speakCues() }
            }
            cue("play.circle", "Run start", "When an agent starts a new task.", "sound.startStyle", SoundStyles.runStart, .start)
            GSDivider()
            cue("hand.raised", "Requests", "When an agent needs a permission or an answer.", "sound.approvalStyle", SoundStyles.requests, .approval)
            GSDivider()
            cue("checkmark.bubble", "Your answer", "When you approve or deny a request.", "sound.answerStyle", SoundStyles.answer, .answer)
            GSDivider()
            cue("checkmark.seal", "Completion", "The chime for a task completed successfully.", "sound.doneStyle", SoundStyles.done, .done)
            GSDivider()
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say which extra sounds") { ExtraSoundVoice.speakExtra() }
            }
            GSToggleRow(symbol: "timer", title: "Timer alarms", text: "A sound when a focus round ends.", isOn: bool("sound.timer"))
            GSDivider()
            GSToggleRow(symbol: "exclamationmark.octagon", title: "Failure sound", text: "A short sound when an agent turn fails.", isOn: bool("sound.failure"))
            GSDivider()
            GSToggleRow(symbol: "play.circle", title: "Chime when an agent starts working", text: "Off by default; busy sessions start often.", isOn: bool("sound.agentStart"))
            GSDivider()
            GSToggleRow(symbol: "waveform", title: "Ambient loop while an agent works", text: "A quiet loop under a running agent, at half volume.", isOn: bool("sound.runningLoop"))
        }
        // These switches still gate playback (ZeusSound.play), whatever style a cue above is set to.
        GSCard("Which events play a sound") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say which events play a sound") { ExtraPreferences.speakEvents() }
            }
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
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say which voice cues play") { ExtraPreferences.speakVoiceCues() }
            }
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
        // Shaping does not depend on Zeus's own sounds, so this card sits outside the dimmed cards above.
        GSEqualiserCard(controller: context.equaliser(), isOn: bool("audio.equaliser"))
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
            GSRow(symbol: "iphone", title: "iPhone app", text: "Pairing needs the Zeus iPhone app on your phone.") {
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
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how agent notices are set") { NotifySetupVoice.speakNotices() }
            }
            // The old Permission requests and Finished tasks switches had no reader: nothing ever checked them. An agent
            // waits for the answer to a request, so it always shows; finished-task banners follow "Show system notifications".
            GSRow(symbol: "hand.raised", title: "Permission requests", text: "Always shown on the notch, because the agent waits for your answer.") {
                GSStatus(ok: true, text: "Always on")
            }
            GSDivider()
            GSRow(symbol: "checkmark.circle", title: "Finished tasks", text: "A macOS banner when an agent finishes, if Show system notifications below is on.")
            GSDivider()
            GSToggleRow(symbol: "exclamationmark.triangle", title: "Errors and stuck agents",
                        text: "A halo and a card, plus a notification when macOS allows it.", detail: "The halo is red or amber.", isOn: bool("notify.errors"))
            GSDivider()
            GSRow(symbol: "hourglass", title: "Mark an agent stuck after", text: "A working agent with no activity for this long turns amber.") {
                GSPopup(selection: SettingsStore.binding("notify.stallMinutes"), options: AgentStall.choices).popupLabel("Mark an agent stuck after")
            }
            GSDivider()
            GSToggleRow(symbol: "eye.slash", title: "Stay quiet while sharing or in full screen",
                        text: "Holds back banners during a call or a full-screen app.", detail: "Also holds them back on a mirrored display, for usage, rain and access alerts.",
                        isOn: Binding(get: { ExtraPreferences.shared.quietWhileSharing }, set: { ExtraPreferences.shared.quietWhileSharing = $0 }))
        }
        GSCard("System notifications") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how system notifications are set") { BannerSetupVoice.speakBanners() }
            }
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
                        Button("Open System Settings") { systemNotifications.openSystemSettingsAfterUserAction() }
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
    /// Mirrors the Chat choice for SwiftUI: the monitor itself is not observable.
    @State private var chat = ChatHotkeyMonitor.shared.hotkey
    @State private var chatProblem = ChatHotkeyMonitor.shared.problem
    /// Why the key the owner just recorded for the second talk key was not kept, and a count that redraws the page when it changes.
    @State private var secondTalkRefusal: String?
    @State private var secondTalkRevision = 0

    /// The Chat choices as the menu names them.
    private static func title(_ key: ChatHotkey) -> String { key.menuTitle }

    /// What the page reads from the keys right now: the chord, the Chat clash and the sentences for the Talk row.
    private struct Routing {
        let chord: Shortcut?
        let clash: VoiceKey.ChatClash?
        let talkNotes: [String]
        let secondTalk: Shortcut?
        let secondTalkNotes: [String]
        /// Plain sentences for the second key, without the warning style.
        let secondTalkQuietNotes: [String]
    }

    /// The sentence under the second talk key when another key has it (`VoiceKey.secondTalkKey` named the key it gave way to).
    private static func yieldNote(_ name: String) -> String {
        switch name {
        case "VoiceOver": "VoiceOver uses Control and Option, so this key is off."
        case "Chat": "Chat uses Option-Space, so this key is off. Record another key or move Chat."
        case "Talk to Zeus": "This is already your Talk to Zeus key, so this key is off. Record another key."
        default: "\(name) uses this key, so it is off. Record another key or change \(name.lowercased())."
        }
    }

    private func routing() -> Routing {
        let talk = Preferences.shared.pushToTalk
        let dictation = DictationSettings.shared
        let voiceOverOn = NSWorkspace.shared.isVoiceOverEnabled
        let heard = VoiceKey.effectiveTalkKey(chosen: talk, dictation: dictation.enabled ? dictation.key : nil,
                                              pointing: PointingSettings.enabled ? PointingSettings.shortcut : nil,
                                              voiceOverOn: voiceOverOn)
        let shared = dictation.enabled && talk == dictation.key
        let routing = TalkChordRouting.current(heard: heard, shared: shared)
        let clash = VoiceKey.chatClash(talk: talk, heard: heard, chat: chat, shared: shared, voiceOverOn: voiceOverOn, holders: [])
        var notes: [String] = []
        if let clash { notes.append(clash.sentence) }
        if let holder = routing.heldBy, holder != "Chat" {
            notes.append("\(holder) uses Control-Option-Space, so it does not talk. Hold Control + Option alone to talk.")
        }
        if let problem = TalkChordHotkey.shared.problem { notes.append(problem) }
        let second = SecondTalkRouting.current()
        var secondNotes: [String] = []
        if let refusal = secondTalkRefusal { secondNotes.append(refusal) }
        var quietNotes: [String] = []
        if let name = second.yieldsTo {
            if VoiceKey.secondTalkNoteIsQuiet(yieldsTo: name, explicit: ShortcutStore.loadSecondTalk(.standard).explicit) {
                quietNotes.append("Off: it is the same as your talk key.")
            } else {
                secondNotes.append(Self.yieldNote(name))
            }
        }
        secondNotes += TilingKeyClash.notes(base: TileModifierBase(label: SettingsStore.shared.string("tiling.keyBase")))
            .filter { $0.contains("Second talk") }
        if second.key != nil { secondNotes.append("Hold it a quarter second before speaking.") }
        return Routing(chord: routing.chord, clash: clash, talkNotes: notes, secondTalk: second.key, secondTalkNotes: secondNotes,
                       secondTalkQuietNotes: quietNotes)
    }

    var body: some View {
        let _ = secondTalkRevision
        let state = routing()
        let clash = state.clash
        GSPageHeading(section: .shortcuts, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        GSCard("Summon Zeus") {
            ShortcutRecorderRow(symbol: "mic.fill", title: "Talk to Zeus",
                                text: "Hold to ask, then let go to send.", detail: "Zeus answers aloud, and if you point at something while you hold, it sees what you mean."
                                    + (state.chord != nil ? " Control + Option + Space does the same." : ""),
                                shortcut: Preferences.shared.pushToTalk, defaultValue: ShortcutStore.talkDefault,
                                otherName: "Dictation", other: DictationSettings.shared.key,
                                voiceOverFallback: VoiceKey.effectiveTalkKey(chosen: Preferences.shared.pushToTalk,
                                                                             dictation: DictationSettings.shared.key,
                                                                             pointing: nil, voiceOverOn: true),
                                notes: state.talkNotes) {
                if let new = $0 { Preferences.shared.chooseTalkKey(new) }
            }
            GSDivider()
            ShortcutRecorderRow(symbol: "mic", title: "Second talk key",
                                text: "Hold to talk, let go to send, and double-tap to keep listening.", detail: "Left Option and Right Option with a letter still type as usual.",
                                shortcut: Preferences.shared.secondTalkKey, defaultValue: ShortcutStore.secondTalkDefault, allowsOff: true,
                                otherName: "Talk to Zeus", other: Preferences.shared.pushToTalk,
                                notes: state.secondTalkNotes, quietNotes: state.secondTalkQuietNotes) { new in
                let dictation = DictationSettings.shared, polyglot = PolyglotSettings.shared
                secondTalkRefusal = new.flatMap {
                    VoiceKey.secondTalkRefusal($0, talk: Preferences.shared.pushToTalk, dictation: dictation.enabled ? dictation.key : nil,
                                               polyglot: polyglot.enabled ? polyglot.hotkey : nil)
                }
                if secondTalkRefusal == nil { Preferences.shared.chooseSecondTalkKey(new) }
                secondTalkRevision += 1
            }
            GSDivider()
            GSRow(symbol: "bubble.left.and.bubble.right", title: "Open the chat window",
                  text: "Opens the chat window from any app.") {
                HStack(spacing: 8) {
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the chat shortcut") { ChatHotkeyMonitor.speakChat() }
                    GSPopup(selection: Binding(get: { Self.title(chat) },
                                               set: { value in
                                                   guard let new = ChatHotkey.allCases.first(where: { Self.title($0) == value }) else { return }
                                                   ChatHotkeyMonitor.shared.set(new)
                                                   chat = new
                                                   chatProblem = ChatHotkeyMonitor.shared.problem
                                               }),
                            options: ChatHotkey.allCases.map { Self.title($0) }, label: "Open the chat window shortcut")
                }
            }
            if let clash {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 11.5))
                    Text(clash.sentence).font(OB.font(13)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(clash.fix == .off ? "Turn Chat off" : "Move Chat to \(Self.title(clash.fix))") {
                        ChatHotkeyMonitor.shared.set(clash.fix)
                        chat = clash.fix
                        chatProblem = ChatHotkeyMonitor.shared.problem
                    }
                    .buttonStyle(GSButtonStyle())
                }
                .foregroundStyle(Theme.ember)
                .padding(.vertical, 6)
            }
            if let chatProblem {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 11.5))
                    Text(chatProblem).font(OB.font(13)).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.ember)
                .padding(.vertical, 6)
            }
            GSDivider()
            ShortcutRecorderRow(symbol: "keyboard", title: "Dictation", text: "Hold to speak, let go to write it where your cursor is.",
                                shortcut: DictationSettings.shared.key, defaultValue: .rightCommand, allowsOff: true,
                                otherName: "Talk to Zeus", other: Preferences.shared.pushToTalk) {
                DictationSettings.shared.key = $0
            }
        }
        GSCard("Keyboard shortcut") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the agent picker shortcut") { PickerSetupVoice.speakPicker() }
            }
            GSRow(symbol: "rectangle.and.hand.point.up.left", title: "Open the agent picker") {
                GSPopup(selection: Binding(get: { ExtraPreferences.shared.openNotch.title },
                                           set: { value in ExtraPreferences.shared.openNotch = ShortcutPreset.allCases.first { $0.title == value } ?? .optionCommandZ }),
                        options: ShortcutPreset.allCases.map(\.title))
            }
        }
        GSCard("Answer from the keyboard") {
            GSToggleRow(symbol: "keyboard", title: "Answer permissions from the keyboard", text: "Approve, deny or open a request with a key while its card is waiting.", isOn: bool("shortcut.answerKeys"))
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
        GSPageHeading(section: .integrations, subtitle: "")
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
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say which agents are offered") { OfferSetupVoice.speakOffer() }
            }
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
    let navigation: GSNavigation
    private var settings: DictationSettings { DictationSettings.shared }

    var body: some View {
        GSPageHeading(section: .murmure, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        GSCard("Dictation") {
            GSToggleRow(symbol: "mic", title: "Enable dictation",
                        text: "A cloud engine sends your audio to its provider.", detail: "Apple Speech and downloaded engines run on this Mac.",
                        isOn: Binding(get: { settings.enabled }, set: { settings.enabled = $0 }))
            if !(context.services.granted(.microphone) && context.services.granted(.accessibility)) {
                GSInfo(text: "Microphone and Accessibility access are required.")
            }
        }
        SpeechEngineCard(compact: true, navigation: navigation)
        GSCard("Murmure") {
            ShortcutLinkRow(symbol: "keyboard", title: "Dictation shortcut", current: settings.key, navigation: navigation)
            GSDivider()
            KeyAccessLinkRow(navigation: navigation)
        }
        GSCard("Language and feedback") {
            GSToggleRow(symbol: "speaker.wave.1", title: "Play dictation sounds", text: "A short cue when recording starts and ends.",
                        isOn: Binding(get: { settings.sounds }, set: { settings.sounds = $0 }))
            GSDivider()
            GSRow(symbol: "globe", title: "Dictation language", text: "Automatic follows macOS, and chosen languages go to Whisper.", detail: "Parakeet applies a script hint where supported.") {
                HStack(spacing: 8) {
                    GSPopup(selection: Binding(get: { settings.language.title },
                                               set: { value in settings.language = DictationLanguage(persistedValue: value) }),
                            options: DictationLanguage.allCases.map(\.title)).popupLabel("Dictation language")
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how dictation is set") { DictationSettings.speakSetup() }
                }
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
    let navigation: GSNavigation
    var body: some View {
        GSPageHeading(section: .voice, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        ZeusVoiceCards(navigation: navigation)
        GSCard("Talk to Zeus") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how talk sight is set") { TalkSightVoice.speakSight() }
            }
            ShortcutLinkRow(symbol: "bolt", title: "Talk to Zeus", current: Preferences.shared.pushToTalk, navigation: navigation)
            GSDivider()
            TalkMicrophoneRow()
            GSDivider()
            GSToggleRow(symbol: "eye", title: "Let Zeus see my screen when I talk",
                        text: "Each question can include the screen, so Zeus can see what you see.", detail: "Off answers without looking. The screenshot is never saved.",
                        isOn: bool("talk.seeScreen"))
            GSDivider()
            GSToggleRow(symbol: "pencil.and.outline", title: "Draw on the screen while Zeus answers",
                        text: "Zeus can ring, arrow, or label what it talks about.", detail: "Off draws nothing. Marks leave a few seconds after the answer.",
                        isOn: bool("talk.drawOnScreen"))
            GSDivider()
            KeyAccessLinkRow(navigation: navigation)
        }
        WakeWordCard()
        GSCard("Approval keywords") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how approval words are set") { KeywordSetupVoice.speakWords() }
            }
            GSToggleRow(symbol: "waveform", title: "Listen for approval keywords",
                        text: "This opens the microphone only while a card is waiting.", detail: "Say a keyword such as yes or no. Off until you turn it on.",
                        isOn: bool("voice.answers"))
            if store.bool("voice.answers"), VoicePermissions.access != .ready {
                GSInfo(text: "Microphone and speech recognition are not allowed yet.")
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

/// Which microphone talk turns use. Automatic follows the system input; This Mac's microphone keeps a Bluetooth headset out of
/// the talk turn. The inputs are listed off the main thread when the page shows, like the Dictation page.
private struct TalkMicrophoneRow: View {
    private var devices: [MicrophoneDevice] { MicrophoneTester.shared.devices }
    private var choice: TalkMicrophoneChoice { TalkMicrophoneChoice(stored: store.string(TalkMicrophoneChoice.settingID)) }

    var body: some View {
        GSRow(symbol: "mic.circle", title: "Microphone",
              text: "Automatic uses the system input, so a headset can win.", detail: "This Mac's microphone keeps a headset from switching mode. Dictation has its own.") {
            HStack(spacing: 8) {
                GSPopup(selection: Binding(get: { choice.title(devices: devices) },
                                           set: { title in
                                               guard let new = TalkMicrophoneChoice.choice(forTitle: title, devices: devices) else { return }
                                               store.set(TalkMicrophoneChoice.settingID, new.stored)
                                           }),
                        options: choice.options(devices: devices), label: "Talk microphone")
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the talk microphone") { TalkMicVoice.speakMic() }
            }
        }
        .onAppear { Task { MicrophoneTester.shared.devices = await Task.detached(priority: .userInitiated) { Microphones.all() }.value } }
    }
}

/// "Listen for “Hey Zeus”": off until turned on; the phrase is heard on this Mac, the request that follows is a normal one.
private struct WakeWordCard: View {
    private var wake: WakeWordController { WakeWordController.shared }

    var body: some View {
        GSCard("Hey Zeus") {
            GSRow(symbol: "ear", title: "Listen for \u{201C}Hey Zeus\u{201D}",
                  text: "Nothing is sent while Zeus waits for the phrase.", detail: "Say the phrase, then your request. Off until you turn it on.") {
                HStack(spacing: 8) {
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say whether Hey Zeus is on") { wake.speakWake() }
                    Toggle("Listen for Hey Zeus", isOn: Binding(get: { wake.enabled }, set: { wake.enabled = $0 }))
                        .toggleStyle(GSToggleStyle()).labelsHidden()
                }
            }
            if wake.enabled {
                GSDivider()
                GSRow(symbol: wake.listening ? "waveform" : "pause.circle", title: "Status", text: statusNote) {
                    GSStatus(ok: wake.listening, text: wake.listening ? "Listening" : wake.needsPermissions ? (VoicePermissions.access == .needsPrompt ? "Not asked yet" : "Denied") : "Paused")
                }
            }
            GSInfo(text: "macOS shows the microphone indicator while the wake phrase listens.")
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
        GSPageHeading(section: .license, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        GSCard("Your license") {
            GSRow(symbol: "key", title: status, text: license.isLicensed ? "Your license is kept across updates." : "A one-time purchase for two Macs.") {
                HStack(spacing: 8) {
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say whether Zeus is licensed") { license.speakLicense() }
                    if license.isLicensed || license.deactivationError != nil {
                        GSDeactivateLicenseControl()
                    }
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
                GSInfo(text: "One license covers 2 Macs.")
            }
        }
    }

    private var status: String { license.statusTitle }
}

// MARK: Permissions

/// The waves speak the style and whether system audio is allowed. They do not ask or start the spectrum.
enum WavesSetupVoice {
    static var speakWaves: () -> Void = {}
}

/// The other notch lights speak mute, the system HUD, the edge, peeks, and an added event. They do not change them.
enum HudExtraVoice {
    static var speakExtras: () -> Void = {}
}

/// The four extra agent sounds speak their switches. Nothing is played.
enum ExtraSoundVoice {
    static var speakExtra: () -> Void = {}
}

/// The talk microphone speaks Automatic, this Mac, a chosen input, or unavailable. It does not start listening.
enum TalkMicVoice {
    static var speakMic: () -> Void = {}
}

/// Whether talk can see the screen, and whether it draws while answering. Nothing is captured.
enum TalkSightVoice {
    static var speakSight: () -> Void = {}
}

/// The halo entrance speaks the animation. It does not play it or change it.
enum HaloEntranceVoice {
    static var speakEntrance: () -> Void = {}
}

/// The halo measures speak strength, speed, and thickness. They do not play the entrance.
enum HaloMeasureVoice {
    static var speakMeasure: () -> Void = {}
}

/// The halo wash speaks the wallpaper match and the edge wave. It does not sample the desktop or flash the wave.
enum HaloWashVoice {
    static var speakWash: () -> Void = {}
}

/// Arrival lights speak the AirDrop glow, the screenshot cue, and whether those folders were asked. Nothing is listed.
enum ArrivalLightsVoice {
    static var speakLights: () -> Void = {}
}

/// Sound feedback speaks the master switch and the cue volume. It does not play a sound.
enum FeedbackSetupVoice {
    static var speakFeedback: () -> Void = {}
}

/// System banners speak the Zeus switch, banner dismiss, and whether any apps are chosen. App names stay unspoken.
enum BannerSetupVoice {
    static var speakBanners: () -> Void = {}
}

/// Approval keywords speak listening and whether each list is still the default. Custom words stay unspoken.
enum KeywordSetupVoice {
    static var speakWords: () -> Void = {}
}

/// Privacy speaks project details, synced lyrics, and Chrome media. It does not fetch or change them.
enum ShareSetupVoice {
    static var speakShare: () -> Void = {}
}

/// New chats speak whether Claude Code and Codex are offered and connected. Nothing is connected or changed.
enum OfferSetupVoice {
    static var speakOffer: () -> Void = {}
    static var claudeConnected: () -> Bool = { false }
    static var codexConnected: () -> Bool = { false }
}

/// Automation speaks Music, Spotify, Keynote, and PowerPoint. It does not ask macOS.
enum ScriptSetupVoice {
    static var speakScript: () -> Void = {}
}

/// Location, Full Disk Access, and key access speak their states. Nothing is requested.
enum LocalAccessVoice {
    static var speakLocal: () -> Void = {}
}

/// The default agent for a new chat speaks Claude Code or Codex. It does not open a chat.
enum DefaultAgentVoice {
    static var speakAgent: () -> Void = {}
}

/// The agent picker shortcut and keyboard answers speak together. They do not change a shortcut.
enum PickerSetupVoice {
    static var speakPicker: () -> Void = {}
}

/// Accessibility, Calendar, and Reminders speak their states. Nothing is requested.
enum GrantVoice {
    static var speakGrants: () -> Void = {}
}

/// Microphone, speech recognition and the camera speak their states. Nothing is requested.
enum AccessVoice {
    static var speakAccess: () -> Void = {}

    /// The three Access rows. Reading them does not raise a prompt.
    static func parts() -> (mic: String, speech: String, camera: String) {
        func word(_ state: PermissionState) -> String {
            switch state {
            case .authorized: "Allowed"
            case .denied: "Denied"
            case .notDetermined: "Not asked yet"
            }
        }
        let camera = PermissionsModel.CaptureAccess.live.camera()
        return (word(VoicePermissions.mic), word(VoicePermissions.speech), word(camera))
    }
}

private struct PermissionsPage: View {
    let context: GSContext
    var body: some View {
        GSPageHeading(section: .permissions, subtitle: "")
            .padding(.bottom, -GS.cardGap)
            .task {
                while !Task.isCancelled {
                    context.refresh()
                    context.sweep?.refreshProgress()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        if let sweep = context.sweep { allowAll(sweep) }
        GSCard("Access") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say the microphone, speech and camera permissions") { AccessVoice.speakAccess() }
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say accessibility, calendar and reminders") { GrantVoice.speakGrants() }
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say location, disk and key access") { LocalAccessVoice.speakLocal() }
            }
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
            perm("internaldrive", "Full Disk Access", "Lets Zeus read banners from other apps for the notification mirror. Optional.", context.services.fullDiskAccess) { context.services.allowFullDiskAccess() }
            GSDivider()
            voicePerm("mic", "Microphone", "Hey Zeus, the talk key and dictation", VoicePermissions.mic, .microphone)
            GSDivider()
            voicePerm("waveform", "Speech recognition", "Turns what you say into words on this Mac", VoicePermissions.speech, .speech)
            GSDivider()
            capturePerm("camera", "Camera", "Records you while you read in the teleprompter", context.permissions.cameraPermissionState, .camera) {
                context.permissions.request(.camera)
            }
            GSDivider()
            capturePerm("rectangle.dashed.badge.record", "Screen Recording", "Screenshots during a turn and system audio for Waves", context.permissions.screenPermissionState, .screen, speak: { PermissionsModel.speakScreen() }) {
                context.permissions.request(.screen)
            }
            GSDivider()
            GSRow(symbol: "keyboard", title: "Keys from other apps", text: "Lets Zeus see the talk and dictation shortcuts.", detail: "Accessibility or Input Monitoring is enough.") {
                HStack(spacing: 10) {
                    GSStatus(ok: KeyListenAccess.granted, text: KeyListenAccess.granted ? (KeyListenAccess.accessibility ? "Accessibility" : "Input Monitoring") : "Not allowed")
                    if !KeyListenAccess.granted {
                        Button("Allow Input Monitoring") { KeyListenAccess.requestInputMonitoring() }.buttonStyle(GSButtonStyle())
                    }
                }
            }
            GSDivider()
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say which apps Zeus can script") { ScriptSetupVoice.speakScript() }
            }
            GSRow(symbol: "music.note", title: "Automation",
                  text: context.permissions.automationMessage
                    ?? "Control playback and read slide notes while those apps are open.", detail: "macOS asks about each app only while it is open.") {
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

    /// One button for everything: macOS still asks for each, but Zeus asks in turn, opens the right pane
    /// and moves on by itself (PermissionSweep).
    private func allowAll(_ sweep: PermissionSweepRunner) -> some View {
        let text: String
        let detail: String?
        if sweep.needsRestart {
            text = "Screen Recording starts working after Zeus reopens."
            detail = nil
        } else if sweep.isRunning {
            text = "Follow the guide at the top of the screen."
            detail = "Skip anything you do not want."
        } else if sweep.allAllowed {
            text = "Everything Zeus can use is allowed."
            detail = nil
        } else {
            text = "Asks for everything at once, one prompt after another."
            detail = "Click Allow in each prompt, or turn on the switch Zeus opens."
        }
        return GSCard {
            GSRow(symbol: "checkmark.shield", title: sweep.progressLine, text: text, detail: detail) {
                if sweep.needsRestart {
                    Button("Restart Zeus now") { sweep.restartZeus() }.buttonStyle(GSButtonStyle(prominent: true))
                } else if sweep.isRunning {
                    Button("Stop") { sweep.cancel() }.buttonStyle(GSButtonStyle()).accessibilityLabel("Stop allowing")
                } else if !sweep.allAllowed {
                    Button("Allow all") { sweep.start() }.buttonStyle(GSButtonStyle(prominent: true))
                        .accessibilityHint("Asks macOS for each access in turn and opens System Settings where a switch is needed.")
                }
            }
        }
    }

    /// "Allowed: Music, Spotify": the apps macOS lets Zeus script (access is per app, so it can be partial).
    private var automationStatus: String {
        let names = context.permissions.automationAllowedNames
        return names.isEmpty ? "Allowed" : "Allowed: " + names.joined(separator: ", ")
    }

    /// Allowed / Not asked yet (Allow raises macOS's one prompt) / Refused (Allow opens the pane).
    private func voicePerm(_ symbol: String, _ title: String, _ text: String, _ state: PermissionState, _ kind: PermissionsModel.Kind) -> some View {
        GSRow(symbol: symbol, title: title, text: state == .denied ? "Turn \(title) on under Privacy in System Settings." : text) {
            switch state {
            case .authorized: GSStatus(ok: true, text: "Allowed")
            case .notDetermined:
                Button("Allow") { Task { await VoicePermissions.ensure(explicit: true); context.refresh() } }.buttonStyle(GSButtonStyle())
                    .accessibilityLabel("Allow \(title)")
            case .denied:
                HStack(spacing: 10) {
                    GSStatus(ok: false, text: "Denied")
                    Button("Open System Settings") { context.permissions.open(kind) }.buttonStyle(GSButtonStyle()).accessibilityLabel("Open \(title) settings")
                }
            }
        }
    }

    /// Camera and Screen Recording: request-only (never starts capture).
    private func capturePerm(_ symbol: String, _ title: String, _ text: String, _ state: PermissionState, _ kind: PermissionsModel.Kind, speak: (() -> Void)? = nil, allow: @escaping () -> Void) -> some View {
        GSRow(symbol: symbol, title: title, text: state == .denied ? "Turn \(title) on under Privacy in System Settings." : text) {
            HStack(spacing: 8) {
                if let speak {
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say whether the screen can be seen") { speak() }
                }
                switch state {
                case .authorized: GSStatus(ok: true, text: "Allowed")
                case .notDetermined:
                    Button("Allow", action: allow).buttonStyle(GSButtonStyle()).accessibilityLabel("Allow \(title)")
                case .denied:
                    HStack(spacing: 10) {
                        GSStatus(ok: false, text: "Denied")
                        Button("Open System Settings") { context.permissions.open(kind) }.buttonStyle(GSButtonStyle()).accessibilityLabel("Open \(title) settings")
                    }
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

/// The closed notch speaks its drop and the waves' sensitivity. It does not move the bar.
enum NotchFitVoice {
    static var speakFit: () -> Void = {}
}

/// Command-line control speaks the switch and the reset notice. It does not turn the switch on or dismiss the notice.
enum CommandSetupVoice {
    static var speakCommand: () -> Void = {}
}

private struct PrivacyPage: View {
    let context: GSContext
    @AppStorage(DriveAutonomy.settingsKey) private var driveAutonomy = DriveAutonomy.default.rawValue
    private var cliAccess: CLIAccessModel { CLIAccessModel.shared }

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
                        text: "Turn off to hide commands and project names on cards.", detail: "Meeting mode hides them too.", isOn: bool("privacy.details"))
        }
        GSCard("Music") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say what Zeus shares") { ShareSetupVoice.speakShare() }
            }
            GSToggleRow(symbol: "text.quote", title: "Synced lyrics",
                        text: "Sends the song title and artist to fetch lyrics kept on this Mac.", detail: "Off until you turn it on.",
                        isOn: bool("privacy.lyrics"))
            GSDivider()
            GSToggleRow(symbol: "globe", title: "Show media playing in Chrome",
                        text: "Reads the title and artist through the Zeus extension.", detail: "Covers load from the page and are not saved. Calls are never shown.",
                        isOn: bool("music.browserMedia"))
            if let reload = store.statusOverrides[BrowserMediaFeed.statusID] {
                GSDivider()
                GSRow(symbol: "arrow.clockwise", title: "Zeus extension", text: reload.1) {
                    Button("Open extensions") { store.actions["music.openExtensions"]?() }.buttonStyle(GSButtonStyle())
                }
            }
        }
        GSFacePresenceCardHost()
        GSCard("Control from the notch") {
            GSRow(symbol: "accessibility", title: "Accessibility", text: "Lets Zeus press keys and click when you ask it to drive the Mac.", detail: "Off until you allow it in System Settings.") {
                Button("Open Accessibility settings") { store.actions["privacy.openAccessibility"]?() }.buttonStyle(GSButtonStyle())
            }
            GSDivider()
            GSRow(symbol: "cursorarrow.motionlines", title: "When Zeus may drive your Mac",
                  text: (DriveAutonomy(rawValue: driveAutonomy) ?? .default).explanation) {
                HStack(spacing: 8) {
                    GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say when Zeus may drive") { DriveController.speakDrive() }
                    GSPopup(selection: autonomyTitle, options: DriveAutonomy.allCases.map(\.title)).popupLabel("When Zeus may drive your Mac")
                }
            }
        }
        GSCard("Command line") {
            HStack {
                Spacer(minLength: 0)
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Say how command-line control is set") { CommandSetupVoice.speakCommand() }
            }
            if cliAccess.noticePending {
                GSRow(symbol: "info.circle", title: "Command-line control was reset",
                      text: "This setting lives in your Keychain, and Zeus turned it off once.", detail: "Turn it on again below if you use the zeus command.") {
                    Button("Got it") { cliAccess.dismissNotice() }.buttonStyle(GSButtonStyle())
                }
                GSDivider()
            }
            GSToggleRow(symbol: "terminal", title: "Allow command-line control of sensitive actions",
                        text: cliAccess.failed
                            ? "Zeus could not change this in your Keychain."
                            : "Lets the zeus command use the microphone, record, type and click.",
                        isOn: Binding(get: { cliAccess.enabled }, set: { cliAccess.set($0) }))
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
        LiveDiagnosticsCard(context: context)
        DiagnosticsLogsCard()
        GSCard("Restart the local connection") {
            GSRow(symbol: "arrow.clockwise", title: "Restart the connection", text: "Agents and running tasks keep going in their own apps.") {
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
              text: service.permission == .refused ? "Turn this on under Screen Recording in System Settings." : "Zeus never records or saves the sound; it only measures how loud each pitch is.") {
            switch service.permission {
            case .allowed: GSStatus(ok: true, text: "Allowed")
            case .notAsked:
                Button("Allow") { service.allowPressed() }.buttonStyle(GSButtonStyle()).accessibilityLabel("Allow system audio")
            case .refused:
                HStack(spacing: 10) {
                    GSStatus(ok: false, text: "Denied")
                    Button("Open System Settings") { service.openSystemSettings() }.buttonStyle(GSButtonStyle()).accessibilityLabel("Open system audio settings")
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
              text: status == .denied ? "Turn on Zeus for the Downloads folder in System Settings." : "Blue intake glow and drops the file on the shelf.") {
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
                    Button("Open System Settings") {
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
              text: status == .denied ? "Turn on Zeus for the Desktop folder in System Settings." : "Camera cue and shelf drop for new screenshots.") {
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
                    Button("Open System Settings") {
                        FolderAccess.openSettings()
                    }
                    .buttonStyle(GSButtonStyle())
                }
            }
        }
    }
}
