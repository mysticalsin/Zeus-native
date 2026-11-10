import AppKit
import Observation
import SwiftUI
import ZeusCore

/// The Settings window, in the shared glass look: a sidebar of glossy tiles, a large title,
/// and cards of rows. Every ZEUS feature lives here as a section of the same pattern.
@MainActor @Observable
final class SettingsNavigation {
    enum Section: String, CaseIterable, Identifiable {
        case general, appearance, notifications, sounds, voice, dictation, shortcuts, topBar, todo, memory, teleprompter, agents, stickies, routines, keepAwake, integrations, assistant, intelligence, permissions, privacy, interview, iPhone, diagnostics, license, about
        var id: String { rawValue }

        /// Sections in the sidebar. Interview, iPhone and Intelligence wait for Lane B engine work.
        static var shown: [Section] {
            allCases.filter { ![.interview, .iPhone, .intelligence].contains($0) }
        }

        var title: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .topBar: "Top Bar"
            case .todo: "To-do"
            case .memory: "Memory"
            case .teleprompter: "Prompter"
            case .agents: "Agents"
            case .stickies: "Stickies"
            case .routines: "Routines"
            case .keepAwake: "Keep awake"
            case .voice: "Voice"
            case .dictation: "Dictation"
            case .integrations: "Integrations"
            case .permissions: "Permissions"
            case .privacy: "Privacy"
            case .about: "About"
            case .notifications: "Notifications"
            case .sounds: "Sounds"
            case .shortcuts: "Shortcut"
            case .interview: "Interview"
            case .iPhone: "iPhone"
            case .diagnostics: "Diagnostics"
            case .assistant: "Assistant"
            case .intelligence: "Intelligence"
            case .license: "License"
            }
        }

        var subtitle: String {
            switch self {
            case .general: "How you talk to ZEUS and where it shows up."
            case .appearance: "The notch glow, the bolt, and the little touches."
            case .topBar: "Which tabs the notch opens to, in your order."
            case .todo: "Your list, learning, and morning brief."
            case .memory: "Your second brain vault on this Mac."
            case .teleprompter: "Notes that follow you while you speak."
            case .agents: "Approvals, hooks and how agents ask."
            case .stickies: "Little notes that stick to your screen."
            case .routines: "Prompts ZEUS runs for you on a schedule."
            case .keepAwake: "Timed sessions that stop idle sleep."
            case .voice: "How ZEUS sounds when it answers."
            case .dictation: "Speak anywhere and your words are typed for you."
            case .integrations: "Claude Code approvals, Chrome, and the AI tools on this Mac."
            case .permissions: "What macOS lets ZEUS do. ZEUS only asks from here or during setup."
            case .privacy: "What leaves your Mac and what never does."
            case .about: "Version and credits."
            case .notifications: "What peeks out of the notch, and when it stays quiet."
            case .sounds: "Little sounds for the moments that matter."
            case .shortcuts: "Keys that work from any app."
            case .interview: "Stay private while you share your screen."
            case .iPhone: "ZEUS in your pocket."
            case .diagnostics: "What to send when something looks wrong."
            case .assistant: "Your AI account, model and how replies behave."
            case .intelligence: "Which engine understands your commands, and what it costs."
            case .license: "Your trial, your key, and this Mac."
            }
        }

        var icon: (String, Color) {
            switch self {
            case .general: ("slider.horizontal.3", Theme.accent)
            case .appearance: ("circle.lefthalf.filled", Theme.accent)
            case .topBar: ("rectangle.topthird.inset.filled", Theme.glow)
            case .voice: ("waveform", Theme.accent)
            case .dictation: ("mic.fill", Theme.glow)
            case .integrations: ("link", Color(hex: 0x22B07D))
            case .permissions: ("lock.fill", Color(hex: 0x64748B))
            case .privacy: ("checkmark.shield.fill", Color(hex: 0x16A34A))
            case .about: ("bolt.fill", Theme.bolt)
            case .notifications: ("bell.badge.fill", Color(hex: 0xF43F5E))
            case .sounds: ("speaker.wave.2.fill", Color(hex: 0xEC4899))
            case .shortcuts: ("command", Theme.glow)
            case .interview: ("person.2.wave.2.fill", Color(hex: 0x14B8A6))
            case .iPhone: ("iphone", Color(hex: 0x94A3B8))
            case .diagnostics: ("stethoscope", Color(hex: 0xF97316))
            case .assistant: ("sparkles", Theme.accent)
            case .intelligence: ("brain.head.profile", Theme.bolt)
            case .license: ("key.fill", Theme.bolt)
            case .todo: ("checklist", Theme.accent)
            case .memory: ("brain.head.profile", Theme.glow)
            case .teleprompter: ("text.alignleft", Theme.accent)
            case .agents: ("bolt.fill", Theme.bolt)
            case .stickies: ("note.text", Theme.glow)
            case .routines: ("arrow.triangle.2.circlepath", Theme.accent)
            case .keepAwake: ("cup.and.saucer.fill", Theme.glow)
            }
        }
    }

    var section: Section = .general
    /// Sidebar search; while non-empty the detail shows every matching option.
    var query = ""
    /// Bumped by Command F to focus the search field.
    var focusSearch = 0
    /// The section whose reset button is waiting for a second press.
    var confirmReset: Section?
    /// Last import or export result, shown on General.
    var fileNote = ""

    var hits: [SettingOption] { SettingsCatalog.search(query) }

    /// Sections with a hit (or a matching title) while searching; all of them otherwise.
    var visibleSections: [Section] {
        guard !query.isEmpty else { return Section.shown }
        let words = query.lowercased()
        let hitSections = Set(hits.map(\.section))
        return Section.shown.filter { hitSections.contains($0) || $0.title.lowercased().contains(words) }
    }

    func step(_ delta: Int) {
        let list = visibleSections
        guard !list.isEmpty else { return }
        let index = list.firstIndex(of: section) ?? -1
        let next = min(max(index + delta, 0), list.count - 1)
        withAnimation(Glass.spring) { section = list[next] }
    }

    func open(_ target: Section) {
        withAnimation(Glass.spring) { section = target; query = "" }
    }

    func openFirstHit() {
        if let first = hits.first?.section ?? visibleSections.first { open(first) }
    }
}

struct SettingsView: View {
    let connections: ConnectionsModel
    let preferences: Preferences
    var permissions: PermissionsModel? = nil
    @AppStorage(AnnotationController.enabledKey) private var annotateEnabled = true
    @AppStorage(DriveAutonomy.settingsKey) private var driveAutonomy = DriveAutonomy.default.rawValue
    var topBar: TopBarModel? = nil
    var dictation: DictationController? = nil
    var navigation = SettingsNavigation()
    /// Taller only for full-page snapshots.
    var height: CGFloat = SettingsView.size.height
    let openSetup: () -> Void

    static let size = CGSize(width: 900, height: 720)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Glass.hairline).frame(width: 1)
            detail.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top).clipped()
        }
        .background(GlassBackdrop())
        .frame(width: Self.size.width, height: height)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                AvatarView(state: AvatarStatus.shared.current, size: 26)
                Text("ZEUS").font(Glass.font(16, .bold)).tracking(1.2).foregroundStyle(Glass.text)
            }
            .padding(.leading, 10).padding(.bottom, 12)
            SettingsSearchField(navigation: navigation).padding(.bottom, 10)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    let visible = navigation.visibleSections
                    ForEach(SettingsNavigation.Section.shown) { section in
                        item(section).opacity(visible.contains(section) ? 1 : 0.32)
                    }
                }
            }
            Spacer()
            Text("v\(ZeusCoreVersion.string)").font(Glass.caption).foregroundStyle(Glass.tertiary).padding(.leading, 10)
        }
        .padding(.top, 46).padding(.bottom, 16).padding(.horizontal, 10)
        .frame(width: 214)
        .background(Glass.sidebar.opacity(0.55))
    }

    private func item(_ section: SettingsNavigation.Section) -> some View {
        let selected = navigation.section == section
        return Button { withAnimation(Glass.spring) { navigation.section = section } } label: {
            HStack(spacing: 10) {
                GlassIcon(symbol: section.icon.0, tint: section.icon.1, size: 26)
                Text(section.title).font(Glass.font(13.5, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Glass.text : Glass.secondary)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Glass.hairline, lineWidth: 1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Detail

    private var detail: some View {
        let section = navigation.section
        let searching = !navigation.query.isEmpty
        return PageScroll(.vertical) {
            VStack(alignment: .leading, spacing: Glass.gap) {
                if searching {
                    SettingsSearchResults(navigation: navigation)
                } else {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title).font(Glass.largeTitle).foregroundStyle(Glass.text)
                            Text(section.subtitle).font(Glass.body).foregroundStyle(Glass.secondary)
                        }
                        Spacer()
                        SectionResetButton(navigation: navigation, section: section)
                    }
                    .padding(.bottom, 6)
                    if section == .appearance { AppearancePreview(topBar: topBar) }
                    page(section)
                    SettingsOptionCards(section: section)
                    if section == .general { SettingsFileCard(navigation: navigation) }
                }
            }
            .padding(.horizontal, 30).padding(.top, 42).padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .id(searching ? "search" : section.rawValue)
            .transition(.opacity.combined(with: .offset(y: 6)))
        }
        .animation(Glass.spring, value: section)
        .animation(Glass.quick, value: searching)
    }

    @ViewBuilder
    private func page(_ section: SettingsNavigation.Section) -> some View {
        switch section {
        case .general: general
        case .appearance: appearance
        case .topBar: if let topBar { TopBarSettings(topBar: topBar) }
        case .todo: TodoSettingsPage(topBar: topBar)
        case .memory: MemorySettingsPage()
        case .teleprompter: TeleprompterSettingsPage()
        case .agents: AgentsSettingsPage()
        case .stickies: StickiesSettingsPage()
        case .routines: RoutinesSettingsView()
        case .keepAwake: KeepAwakeSettingsPage()
        case .voice: voice
        case .dictation: if let topBar { DictationSettingsView(topBar: topBar, settings: .shared, dictation: dictation) }
        case .integrations: integrations
        case .permissions: permissionsPage
        case .privacy: privacy
        case .about: about
        case .notifications: NotificationsSettings(prefs: .shared)
        case .sounds: SoundsSettings(prefs: .shared, dictation: .shared)
        case .shortcuts: ShortcutSettings(prefs: .shared, preferences: preferences, dictation: .shared)
        case .interview: InterviewSettings(prefs: .shared)
        case .iPhone: IPhoneSettings()
        case .diagnostics: DiagnosticsSettings(permissions: permissions)
        case .assistant: AssistantSettings(account: .shared, drafts: .shared)
        case .intelligence: IntelligenceSettings(center: .shared)
        case .license: LicenseSettings(license: .shared, drafts: .shared)
        }
    }

    private var general: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Talk to ZEUS") {
                GlassRow(title: "Talk key", note: (DictationSettings.shared.enabled && DictationSettings.shared.key == preferences.pushToTalk ? "Double-tap it, then speak. Holding the same key dictates." : "Hold it, ask, let go. ZEUS answers out loud and points.")) {
                    ShortcutRecorderButton(shortcut: preferences.pushToTalk, onChange: { preferences.pushToTalk = $0 }, accessibilityName: "Talk key")
                }
                GlassDivider()
                GlassRow(title: "Show captions next to the bolt") {
                    GlassToggle(isOn: Binding(get: { preferences.showCaptions }, set: { preferences.showCaptions = $0 }), label: "Captions")
                }
            }
            GlassCard(title: "Where ZEUS lives") {
                GlassRow(title: "Show ZEUS in the menu bar",
                         note: preferences.showMenuBarIcon ? nil : "To get back here, open ZEUS again from Applications or Spotlight.") {
                    GlassToggle(isOn: Binding(get: { preferences.showMenuBarIcon }, set: { preferences.showMenuBarIcon = $0 }), label: "Menu bar icon")
                }
                GlassDivider()
                GlassRow(title: "Mini ZEUS beside the notch", note: "The little mascot stays left of the notch even when ZEUS is resting.") {
                    GlassToggle(isOn: Binding(get: { AvatarStatus.shared.alwaysInNotch }, set: { AvatarStatus.shared.alwaysInNotch = $0 }), label: "Bolt in notch")
                }
                GlassDivider()
                GlassRow(title: "Follow my Mac's calendar",
                         note: preferences.followSystemCalendar ? "Dates use your Mac's calendar." : "Dates are Gregorian, like \(ZeusDates.string(Date(), template: "EEEEdMMMM", followSystem: false)).") {
                    GlassToggle(isOn: Binding(get: { preferences.followSystemCalendar }, set: { preferences.followSystemCalendar = $0 }), label: "System calendar")
                }
            }
            GlassCard(title: "Show me and drive") {
                GlassRow(title: "Draw on screen", note: "Hold the left Command key, then circle or underline anything. ZEUS answers about that spot.") {
                    GlassToggle(isOn: $annotateEnabled, label: "Show me")
                }
                GlassDivider()
                GlassRow(title: "Let ZEUS run safe steps", note: "Opening apps, scrolling and typing you can undo run at once. Clicks, shortcuts, menus, switches and filled fields wait for your yes. Esc stops ZEUS.") {
                    GlassToggle(isOn: Binding(get: { driveAutonomy != DriveAutonomy.ask.rawValue },
                                              // Turning it on keeps Trusted when that was chosen in Agents.
                                              set: { driveAutonomy = $0 ? (driveAutonomy == DriveAutonomy.ask.rawValue ? DriveAutonomy.safe.rawValue : driveAutonomy) : DriveAutonomy.ask.rawValue }),
                                label: "Auto-run safe steps")
                }
            }
            GlassCard(title: "Setup") {
                GlassRow(title: "Run setup again", note: "Permissions, your second brain, and a voice. No keys needed.") {
                    Button("Set Up Again", action: openSetup).buttonStyle(GlassButtonStyle(kind: .primary, compact: true))
                }
            }
        }
    }

    private var appearance: some View {
        VStack(spacing: Glass.gap) {
            if let topBar {
                GlassCard(title: "Notch glow") {
                    GlassRow(title: "Glow style", note: "How the notch lights up while agents work or need you.") {
                        GlassMenu(options: TopBarModel.HaloStyle.allCases.map { ($0, $0.title) },
                                  selection: Binding(get: { topBar.haloStyle }, set: { topBar.haloStyle = $0 }))
                    }
                }
                GlassCard(title: "Live touches") {
                    GlassRow(title: "Quick cues", note: "Copy, caps lock, volume and battery flash beside the notch.") {
                        GlassToggle(isOn: Binding(get: { topBar.cuesEnabled }, set: { topBar.cuesEnabled = $0 }), label: "Quick cues")
                    }
                    GlassDivider()
                    GlassRow(title: "What's playing beside the notch") {
                        GlassToggle(isOn: Binding(get: { topBar.liveMusicWings }, set: { topBar.liveMusicWings = $0 }), label: "Music wings")
                    }
                }
            }
            GlassCard(title: "The bolt") {
                Text("ZEUS changes colour with what it is doing.").font(Glass.caption).foregroundStyle(Glass.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 12) {
                    ForEach(AvatarState.allCases) { state in
                        VStack(spacing: 6) {
                            AvatarView(state: state, size: 34, animated: false)
                            Text(state.short).font(Glass.font(10, .medium)).foregroundStyle(Glass.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var voice: some View {
        let settings = VoiceSettings.shared
        let paused = settings.elevenLabsPausedUntil.map { $0 > Date() } ?? false
        let plan = UltronVoicePlan.preferred(kokoroReady: settings.kokoroReady,
                                             elevenLabsKeyValid: settings.elevenKeySaved && !paused)
        return VStack(spacing: Glass.gap) {
            GlassCard(title: "Voice") {
                GlassRow(title: UltronVoicePlan.presetTitle) {
                    GlassStatus(ok: true, text: "Default")
                }
                GlassDivider()
                GlassRow(title: "Engine") {
                    GlassStatus(ok: true, text: UltronVoicePlan.engineLabel(plan, kokoroVoice: settings.kokoroVoice))
                }
                GlassDivider()
                GlassRow(title: "Preview") {
                    Button("Preview") { settings.test(with: ZeusVoiceCards.previewSpeaker) }
                        .buttonStyle(GlassButtonStyle(kind: .primary, compact: true))
                        .accessibilityLabel("Preview the Ultron voice")
                }
            }
        }
    }

    private var integrations: some View {
        VStack(spacing: Glass.gap) {
            if let permissions {
                GlassCard(title: "Claude Code") {
                    GlassRow(title: "Approvals in the notch",
                             note: permissions.hookMessage ?? "Adds ZEUS's hooks to ~/.claude/settings.json, with a backup. Your other hooks stay.",
                             icon: ("terminal.fill", Color(hex: 0xD97757))) {
                        HStack(spacing: 8) {
                            GlassStatus(ok: permissions.claudeHooksInstalled, text: permissions.claudeHooksInstalled ? "Connected" : "Off")
                            Button(permissions.claudeHooksInstalled ? "Disconnect" : "Connect") {
                                if permissions.claudeHooksInstalled { permissions.disconnectClaudeCode() } else { permissions.connectClaudeCode() }
                            }
                            .buttonStyle(GlassButtonStyle(kind: permissions.claudeHooksInstalled ? .secondary : .primary, compact: true))
                        }
                    }
                }
                GlassCard(title: "Chrome") {
                    GlassRow(title: "Bridge", note: permissions.chromeMessage, icon: ("globe", Color(hex: 0x4285F4))) {
                        HStack(spacing: 8) {
                            GlassStatus(ok: permissions.chromeHostInstalled, text: permissions.chromeHostInstalled ? "Registered" : "Off")
                            Button(permissions.chromeHostInstalled ? "Disconnect" : "Connect") {
                                if permissions.chromeHostInstalled { permissions.disconnectChrome() } else { permissions.connectChrome() }
                            }
                            .buttonStyle(GlassButtonStyle(kind: permissions.chromeHostInstalled ? .secondary : .primary, compact: true))
                        }
                    }
                    GlassDivider()
                    GlassRow(title: "Extension", icon: ("puzzlepiece.extension.fill", Color(hex: 0x4285F4))) {
                        HStack(spacing: 8) {
                            GlassStatus(ok: permissions.chromeConnected, text: permissions.chromeConnected ? "Connected" : "Not loaded")
                            if permissions.chromeHostInstalled && !permissions.chromeConnected {
                                Button("Show") { ChromeInstaller.showLoadUnpacked() }.buttonStyle(GlassButtonStyle(kind: .secondary, compact: true))
                            }
                        }
                    }
                }
            }
            GlassCard(title: "AI tools on this Mac") {
                ForEach(Array(connections.connections.enumerated()), id: \.element.id) { index, connection in
                    if index > 0 { GlassDivider() }
                    GlassRow(title: connection.name, note: connection.path ?? "Not installed") {
                        GlassStatus(ok: connection.path != nil, text: connection.path != nil ? "Found" : "Missing")
                    }
                }
                Button("Check Again") { Task { await connections.refresh() } }
                    .buttonStyle(GlassButtonStyle(kind: .secondary, compact: true))
            }
        }
    }

    private var permissionsPage: some View {
        GlassCard {
            if let permissions {
                ForEach(Array(PermissionsModel.Kind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { GlassDivider() }
                    let on = permissions.granted[kind] == true
                    let pending = kind == .automation && permissions.automationPending && !on
                    GlassRow(title: kind.rawValue, note: Self.why(kind), icon: Self.icon(kind)) {
                        HStack(spacing: 8) {
                            if pending {
                                GlassStatus(ok: false, text: "Checking…")
                            } else {
                                GlassStatus(ok: on, text: on ? "On" : "Off")
                            }
                            Button(on ? "Open" : "Turn On") { permissions.request(kind) }
                                .buttonStyle(GlassButtonStyle(kind: on ? .secondary : .primary, compact: true))
                        }
                    }
                }
            }
        }
    }

    static func why(_ kind: PermissionsModel.Kind) -> String {
        switch kind {
        case .microphone: "Hears you only while you hold your talk key."
        case .speech: "Turns your words into text on this Mac."
        case .accessibility: "Notices your talk key and types dictation where you are."
        case .camera: "Records you while you read in the teleprompter."
        case .screen: "Lets ZEUS see what you are asking about, only during a turn."
        case .calendar: "Shows your next events on Home and Calendar, and joins calls in one click."
        case .reminders: "Lists and ticks off Apple Reminders, and mirrors your ZEUS to-dos."
        case .automation: "Plays, pauses and skips in Music and Spotify from the notch."
        }
    }

    static func icon(_ kind: PermissionsModel.Kind) -> (String, Color) {
        switch kind {
        case .microphone: ("mic.fill", Color(hex: 0xEF4444))
        case .speech: ("text.bubble.fill", Color(hex: 0x3B82F6))
        case .accessibility: ("accessibility", Color(hex: 0x2563EB))
        case .camera: ("camera.fill", Color(hex: 0x6366F1))
        case .screen: ("rectangle.dashed.badge.record", Color(hex: 0x8B5CF6))
        case .calendar: ("calendar", Color(hex: 0xF97316))
        case .reminders: ("checklist", Color(hex: 0x10B981))
        case .automation: ("music.note", Color(hex: 0xEC4899))
        }
    }

    private var privacy: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "What leaves your Mac") {
                Text("When you talk to ZEUS (the talk key, \u{201C}Hey Zeus\u{201D} if you turned it on, or a typed chat): the text of what you said or typed, screenshots of your displays when a turn needs them and, when Chrome is in front, the current page's text. They go to Claude through your own claude command line login, or to the engine you chose in Settings \u{203A} Engine.")
                    .font(Glass.body).foregroundStyle(Glass.text).fixedSize(horizontal: false, vertical: true)
            }
            GlassCard(title: "What stays on your Mac") {
                Text("Speech is turned into text on this Mac unless you pick a cloud speech engine for dictation. Dictation history (words and audio) and typed chats are kept on this Mac only; Settings \u{203A} Murmure sets how long and lets you clear it. ZEUS sends no analytics.")
                    .font(Glass.body).foregroundStyle(Glass.text).fixedSize(horizontal: false, vertical: true)
            }
            GlassCard(title: "What ZEUS changes") {
                Text("Connect Claude Code adds hooks to ~/.claude/settings.json and keeps a backup next to it. Connect Chrome registers ZEUS's bridge with Chrome. Disconnect removes only ZEUS's entries.")
                    .font(Glass.body).foregroundStyle(Glass.text).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var about: some View {
        GlassCard {
            HStack(spacing: 16) {
                AvatarView(state: .idle, size: 64, animated: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ZEUS").font(Glass.font(22, .bold)).tracking(1.5).foregroundStyle(Glass.text)
                    Text("Version \(ZeusCoreVersion.string)").font(Glass.body).foregroundStyle(Glass.secondary)
                    Text("Type: Plus Jakarta Sans, SIL Open Font License.").font(Glass.caption).foregroundStyle(Glass.tertiary)
                }
            }
        }
    }
}

/// Which tabs the notch shows, in order, plus weather.
private struct TopBarSettings: View {
    let topBar: TopBarModel

    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Tabs") {
                ForEach(Array(TopBarTab.allCases.enumerated()), id: \.element) { index, tab in
                    if index > 0 { GlassDivider() }
                    let shown = topBar.layout.tabs.contains(tab)
                    // A full row cannot take another tab: the switch would read on while the notch shows nothing new.
                    let blocked = !shown && topBar.layout.isFull()
                    GlassRow(title: tab.title, note: blocked ? "The row holds \(GlanceTopBar.maxTabs) tabs. Turn one off first." : "", icon: (tab.symbol, Theme.accent)) {
                        HStack(spacing: 6) {
                            if shown, tab != .home {
                                arrow("chevron.up", "Move left") { topBar.layout.move(tab, by: -1) }
                                arrow("chevron.down", "Move right") { topBar.layout.move(tab, by: 1) }
                            }
                            GlassToggle(isOn: Binding(get: { shown }, set: { _ in if !blocked { topBar.layout.toggle(tab) } }), label: tab.title)
                                .disabled(tab == .home || blocked).opacity(tab == .home || blocked ? 0.5 : 1)
                        }
                    }
                }
            }
            GlassCard(title: "Weather") {
                GlassRow(title: "City", note: "Forecasts come from Open-Meteo. Only the city name is sent.") {
                    GlassField(placeholder: "City", text: Binding(get: { topBar.weatherCity }, set: { topBar.weatherCity = $0 }),
                               onSubmit: { topBar.refreshWeather() })
                }
                GlassDivider()
                GlassRow(title: "Units") {
                    GlassSegmented(options: [(true, "°C"), (false, "°F")],
                                   selection: Binding(get: { topBar.useCelsius }, set: { topBar.useCelsius = $0 }))
                }
            }
        }
    }

    private func arrow(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Glass.secondary)
                .frame(width: 24, height: 24).background(Circle().fill(Glass.fillRaised))
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

/// Dictation: key, modes, vocabulary, history.
private struct DictationSettingsView: View {
    let topBar: TopBarModel
    let settings: DictationSettings
    let dictation: DictationController?

    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Dictate anywhere") {
                GlassRow(title: "Dictation", note: settings.selectedBehavior == .pressToToggle
                         ? "Press once to start, press again to finish, and use Esc to cancel."
                         : "Hold to dictate, double-tap for hands-free, Esc cancels. Hold Shift as you let go to also press Return.") {
                    GlassToggle(isOn: Binding(get: { settings.enabled }, set: { settings.enabled = $0 }), label: "Dictation")
                }
                GlassDivider()
                GlassRow(title: "Dictation key", note: settings.key == Preferences.shared.pushToTalk ? "Shared with the talk key: hold to dictate, double-tap to talk to ZEUS. Shortcuts like ⌘C are ignored." : nil) {
                    ShortcutRecorderButton(shortcut: settings.key, onChange: { settings.key = $0 }, accessibilityName: "Dictation key")
                }
                GlassDivider()
                let behaviors = settings.availableBehaviors
                GlassRow(title: "Shortcut behavior", note: settings.key == Preferences.shared.pushToTalk
                         ? "The shared talk key keeps hold-to-dictate and double-tap-to-talk. Choose a separate key to enable press-to-toggle."
                         : settings.selectedBehavior.detail) {
                    GlassMenu(options: behaviors.map { ($0, $0.title) },
                              selection: Binding(get: { settings.selectedBehavior }, set: { settings.behavior = $0 }))
                }
                GlassDivider()
                GlassRow(title: "Dictation language", note: "Automatic follows macOS for Apple Speech and lets Whisper detect. Selected languages go to Whisper; Parakeet applies a script hint where supported.") {
                    GlassMenu(options: DictationLanguage.allCases.map { ($0, $0.title) },
                              selection: Binding(get: { settings.language }, set: { settings.language = $0 }))
                }
            }
            SpeechEngineSection(settings: settings, dictation: dictation)
            DictationExtrasSection(settings: settings, topBar: topBar)
            GlassCard(title: "Mode") {
                GlassRow(title: "Default mode", note: "Voice mode stays on this Mac. Other modes rewrite your words with your own Claude login.") {
                    GlassMenu(options: topBar.dictationModes.map { ($0.key, $0.name) },
                              selection: Binding(get: { topBar.selectedModeKey }, set: { topBar.selectedModeKey = $0 }))
                }
                GlassDivider()
                GlassRow(title: "Switch mode by app", note: "Mail uses Email, Messages uses Message.") {
                    GlassToggle(isOn: Binding(get: { settings.autoSwitch }, set: { settings.autoSwitch = $0 }), label: "Switch by app")
                }
                if let dictation {
                    Button("Open Modes Folder") {
                        try? FileManager.default.createDirectory(at: dictation.modesFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(dictation.modesFolder)
                    }
                    .buttonStyle(GlassButtonStyle(kind: .secondary, compact: true))
                }
            }
            GlassCard(title: "Vocabulary") {
                Group {
                    if TopBarStyle.isSnapshot {
                        Text(topBar.vocabularyDraft.isEmpty ? "Superwhisper\nsuper whisper -> Superwhisper" : topBar.vocabularyDraft)
                            .foregroundStyle(Glass.secondary).frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
                    } else {
                        TextEditor(text: Binding(get: { topBar.vocabularyDraft }, set: { topBar.vocabularyDraft = $0 }))
                            .scrollContentBackground(.hidden).frame(height: 90)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Glass.hairline, lineWidth: 1))
                HStack {
                    Text("One word per line, or a fix like “super whisper -> Superwhisper”.").font(Glass.caption).foregroundStyle(Glass.secondary)
                    Spacer()
                    if let dictation {
                        Button("Save") { dictation.vocabulary = Vocabulary.parse(topBar.vocabularyDraft) }
                            .buttonStyle(GlassButtonStyle(kind: .primary, compact: true))
                    }
                }
            }
            GlassCard(title: "Pasting and history") {
                GlassRow(title: "Put the clipboard back after pasting") {
                    GlassToggle(isOn: Binding(get: { settings.restoreClipboard }, set: { settings.restoreClipboard = $0 }), label: "Restore clipboard")
                }
                GlassDivider()
                GlassRow(title: "Play sounds") {
                    GlassToggle(isOn: Binding(get: { settings.sounds }, set: { settings.sounds = $0 }), label: "Sounds")
                }
                GlassDivider()
                GlassRow(title: "Pause music while dictating") {
                    GlassToggle(isOn: Binding(get: { settings.pauseMedia }, set: { settings.pauseMedia = $0 }), label: "Pause music")
                }
                GlassDivider()
                GlassRow(title: "Keep history") {
                    GlassStepper(value: Binding(get: { settings.keepDays }, set: { settings.keepDays = $0 }), range: 1...365,
                                 format: { "\($0) days" })
                }
            }
        }
        .onAppear { if let dictation, topBar.vocabularyDraft.isEmpty { topBar.vocabularyDraft = dictation.vocabulary.editableText } }
    }
}
