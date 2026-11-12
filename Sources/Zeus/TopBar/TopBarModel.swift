import AppKit
import Observation
import SwiftUI
import ZeusCore

/// Everything the notch top bar shows beside agents: Home band, music, calendar, weather,
/// clipboard, shelf, focus and dictation, plus the short cues that light the closed notch.
@MainActor
@Observable
final class TopBarModel {
    @ObservationIgnored private let defaults: UserDefaults
    /// Offscreen snapshots give the Record page its own controller with fake displays; nil in the app.
    @ObservationIgnored var recordlyForSnapshot: RecordlyController?
    struct CalendarItem: Identifiable, Equatable {
        let id: String
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var colorHex: UInt32
        var location: String?
        var meetingURL: URL?
        var calendarName: String? = nil
        var notes: String? = nil
    }

    struct ReminderItem: Identifiable, Equatable {
        let id: String
        var title: String
        var due: Date?
        var done: Bool
    }

    struct ShelfItem: Identifiable, Equatable {
        let id = UUID()
        var url: URL
        var name: String { url.lastPathComponent }
        var isMedia: Bool {
            ["m4a", "mp3", "wav", "aiff", "aif", "caf", "mp4", "mov", "m4v", "flac", "ogg"].contains(url.pathExtension.lowercased())
        }
    }

    struct Battery: Equatable {
        var level: Int
        var charging: Bool
        var pluggedIn: Bool
    }

    /// The phases live in ZeusCore (`DictationFlow` decides them); the top bar only reads the value.
    typealias DictationPhase = ZeusCore.DictationPhase

    enum Access: Equatable { case unknown, granted, denied }

    /// The halo styles live in ZeusCore (one stable id each); the setting is `halo.style`.
    typealias HaloStyle = ZeusCore.HaloStyle

    // MARK: Home customise, tab editor, Calendar page (kept here: this toolchain has no @State)

    /// Home's customise mode: slots wiggle, a click picks a slot, the bar below sets widget, style and backdrop.
    var homeCustomizing = false
    var homePickerSlot: Int?
    /// The notch row's editor: add, remove and drag tabs.
    var tabEditing = false
    var draggedTab: TopBarTab?
    var tabEditorNote: String?
    /// The Calendar page: the month on show, the day picked, the events of the month grid, the one open in details.
    var calendarMonth = Date()
    var calendarDay = Date()
    var calendarEvents: [CalendarItem] = []
    var calendarDetailID: String?
    var quickAddText = ""
    var quickAddNote: String?
    /// Reads a stretch of days from the calendar (wired by the services; empty without access).
    var fetchEvents: (Date, Date) -> [CalendarItem] = { _, _ in [] }
    /// Saves an event; asks for Calendar access only here, the first time (wired by the services).
    var createEvent: (CalendarQuickAdd.Parsed) async -> EventCreateResult = { _ in .failed("Calendar isn't available.") }

    enum EventCreateResult: Equatable {
        case created(id: String)
        /// Access is off (or refused just now): where to turn it on.
        case needsAccess
        case failed(String)
    }

    /// Extra height under Home's cards: the customise bar, or the status strip.
    var homeExtraHeight: CGFloat { homeCustomizing ? HomeCustomize.barHeight + HomeStrip.gap : homeStrip.extraHeight }

    // MARK: Layout and navigation

    var layout: TopBarLayout {
        didSet {
            defaults.set(layout.encoded(), forKey: "topBar.tabs")
            defaults.set(TopBarLayout.knownEncoded(), forKey: "topBar.tabs.known")
        }
    }
    /// Hover and drop-target state for rows, kept here because the toolchain builds without SwiftUI macros.
    var hovered: String?
    /// Glance Clipboard chips: All / Text / Links / Images. Stored here because @State is not
    /// available to this toolchain (see DictateHold).
    typealias ClipboardFilter = ZeusCore.ClipboardFilter
    var clipboardFilter: ClipboardFilter = .all
    var shelfTargeted = false
    var selectedTab: TopBarTab = .home
    /// Snapshots pin a style per model (the setting is shared by every model).
    private var snapshotHalo: HaloStyle?
    /// The notch halo, read from and written to the single `halo.style` setting that every picker uses.
    var haloStyle: HaloStyle {
        get { snapshotHalo ?? HaloStyle.resolve(SettingsStore.shared.string("halo.style")) }
        set { if TopBarStyle.isSnapshot { snapshotHalo = newValue } else { SettingsStore.shared.set("halo.style", newValue.rawValue) } }
    }
    /// Short cues on the closed notch (copy, caps lock, volume, battery, track change).
    var cuesEnabled: Bool {
        didSet { defaults.set(cuesEnabled, forKey: "topBar.cues") }
    }
    /// Music artwork and bars beside the closed notch while something plays.
    var liveMusicWings: Bool {
        didSet { defaults.set(liveMusicWings, forKey: "topBar.musicWings") }
    }
    var weatherCity: String {
        didSet { defaults.set(weatherCity, forKey: "topBar.weatherCity") }
    }
    var useCelsius: Bool {
        didSet { defaults.set(useCelsius, forKey: "topBar.celsius") }
    }

    // MARK: Live data

    var nowPlaying: NowPlaying? {
        didSet { if oldValue?.isPlaying != nowPlaying?.isPlaying { AudioSpectrumService.shared.setMusicPlaying(nowPlaying?.isPlaying == true) } }
    }
    var events: [CalendarItem] = []
    var reminders: [ReminderItem] = []
    var calendarAccess: Access = .unknown
    var weather: WeatherSnapshot?
    var weatherPlace = ""
    var weatherError: String?
    var battery: Battery?
    var clipboard = ClipboardHistory()
    var shelf: [ShelfItem] = []
    var focus = FocusTimer()
    var note: String {
        didSet { defaults.set(note, forKey: "topBar.note") }
    }

    // Dictation
    var dictationPhase: DictationPhase = .idle
    var dictationLevel: Double = 0
    var dictationPartial = ""
    /// Settings' vocabulary editor text, saved explicitly so half-typed lines aren't lost.
    var vocabularyDraft = ""
    var dictationModeName = "Voice"
    var dictationModeSymbol = "waveform"
    var dictationHistory: [DictationRecord] = []
    var dictationModes: [DictationMode] = DictationMode.builtIns
    var selectedModeKey: String {
        didSet { defaults.set(selectedModeKey, forKey: "dictation.mode") }
    }

    // Teleprompter
    var script: String {
        didSet { defaults.set(script, forKey: "prompter.script") }
    }
    var roll: PrompterRoll {
        didSet {
            if roll.speed != oldValue.speed { defaults.set(roll.speed, forKey: "prompter.speed") }
            if roll.voiceFollow != oldValue.voiceFollow, !savingVoiceFallback { defaults.set(roll.voiceFollow, forKey: "prompter.voice") }
        }
    }
    private var savingVoiceFallback = false

    /// The mic can't be used for this run: follow turns off now, but your saved choice stays.
    func fallBackFromVoiceFollow() {
        savingVoiceFallback = true
        roll.voiceFollow = false
        savingVoiceFallback = false
    }

    /// A new run starts from the saved voice-follow choice (a fallback lasted one run only).
    func restoreSavedVoiceFollow() {
        roll.voiceFollow = defaults.object(forKey: "prompter.voice") as? Bool ?? true
    }
    var prompterTextSize: Double {
        didSet { defaults.set(prompterTextSize, forKey: "prompter.size") }
    }
    var prompterHovered = false
    var prompterLevel: Double = 0
    var prompterContentHeight: Double = 0
    var prompterCueOffsets: [Int: CGFloat] = [:]
    var prompterNotice: String?
    /// Where the line being read sits, measured from the top of the page (closest to the camera).
    static let prompterReadingLine: Double = 34
    var prompterActive: Bool { roll.phase != .idle }

    /// Display stays awake while on. Not saved across launches on purpose.
    var keepAwake = false {
        didSet { if keepAwake != oldValue { onKeepAwake(keepAwake) } }
    }

    // Cues
    private(set) var cue: NotchCue?
    private(set) var cueStartedAt = Date.distantPast
    private var cueTask: Task<Void, Never>?

    // Actions the views call; wired by the services so views stay free of system calls.
    var musicCommand: (MusicCommand) -> Void = { _ in }
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var copyText: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    var requestCalendarAccess: () -> Void = {}
    var refreshWeather: () -> Void = {}
    var transcribeFile: (URL) -> Void = { _ in }
    var insertText: (String) -> Void = { _ in }
    var chooseFileToTranscribe: () -> Void = {}
    var startPrompter: () -> Void = {}
    var stopPrompter: () -> Void = {}
    var editScript: () -> Void = {}
    var setPrompterVoice: (Bool) -> Void = { _ in }
    var onKeepAwake: (Bool) -> Void = { _ in }
    /// Selects a tab and opens the panel on it (the wings' Stop uses this for Scribe's confirmation).
    var onOpenTab: (TopBarTab) -> Void = { _ in }
    /// Speaks the daily brief in ZEUS's voice.
    var speakBrief: (String) -> Void = { _ in }
    var openSettings: () -> Void = {}
    /// Opens Settings > Permissions, the only in-app place a permission is asked for.
    var openPermissions: () -> Void = {}
    /// The app routes important cues to macOS only while the notch is closed.
    var onSystemNotification: (NotchCue) -> Void = { _ in }
    /// The notch's dictation button: click to start, click again to stop and type it where you were.
    var toggleDictation: () -> Void = {}

    enum MusicCommand { case playPause, next, previous, open }

    /// Jumps the current track to this many seconds (the progress line's drag).
    var seek: (Double) -> Void = { _ in }
    /// Pops up the list of audio outputs under the pointer.
    var chooseOutputDevice: () -> Void = {}
    /// A menu from the notch (the ... button) is open: the notch stays up while it is.
    var menuOpen = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let knownBefore = defaults.string(forKey: "topBar.tabs.known")
        let saved = TopBarLayout.decode(defaults.string(forKey: "topBar.tabs"), known: knownBefore)
        // Once: put the nine-tab row (Glance's seven, Teleprompter, Insomnia) first in a saved layout.
        // Teleprompter and Insomnia come on; other tabs turned off stay off.
        let reorder = !defaults.bool(forKey: "topBar.row9.v1")
        if reorder, !TopBarStyle.isSnapshot, !StartupPolicy.current.isQA {
            defaults.set(true, forKey: "topBar.row9.v1")
            defaults.set(true, forKey: "topBar.glanceOrder.v1")
        }
        // Once more: Polyglot joins the row after Insomnia (ten tabs).
        let addPolyglot = !defaults.bool(forKey: "topBar.row10.v1")
        if addPolyglot, !TopBarStyle.isSnapshot, !StartupPolicy.current.isQA { defaults.set(true, forKey: "topBar.row10.v1") }
        var upgraded = reorder ? saved.upgradedToNineTabRow() : saved
        if addPolyglot { upgraded = upgraded.upgradedToTenTabRow() }
        let addRecordly = !defaults.bool(forKey: "topBar.row11.v1")
        if addRecordly, !TopBarStyle.isSnapshot, !StartupPolicy.current.isQA { defaults.set(true, forKey: "topBar.row11.v1") }
        if addRecordly { upgraded = upgraded.upgradedToRecordlyRow() }
        let addScribe = !defaults.bool(forKey: "topBar.row12.v1")
        if addScribe, !TopBarStyle.isSnapshot, !StartupPolicy.current.isQA { defaults.set(true, forKey: "topBar.row12.v1") }
        if addScribe { upgraded = upgraded.upgradedToScribeRow() }
        // v2: v1 set its flag without saving the moved row, so Agents fell back past the visible end on relaunch.
        let addAgents = !defaults.bool(forKey: "topBar.row13.v2")
        if addAgents, !TopBarStyle.isSnapshot, !StartupPolicy.current.isQA { defaults.set(true, forKey: "topBar.row13.v2") }
        if addAgents { upgraded = upgraded.upgradedToAgentsRow() }
        // Repair, once per version: an earlier launch saved the flags above without the upgraded row, so on
        // this launch none of them is true and the row would stay old. Only a row that was saved is repaired.
        let needsRepair = defaults.integer(forKey: "topBar.layoutRepair") < TopBarLayoutRepair.version
        var repairedRow = false
        if needsRepair, defaults.string(forKey: "topBar.tabs") != nil {
            let fixed = TopBarLayoutRepair.repaired(upgraded, savedKnown: knownBefore)
            repairedRow = fixed != upgraded
            upgraded = fixed
        }
        layout = upgraded
        // Property observers don't run inside init, so save the upgraded row here. Otherwise the
        // one-time flags above stop the upgrade from running again while the old row stays saved.
        if !TopBarStyle.isSnapshot, !StartupPolicy.current.isQA {
            if reorder || addPolyglot || addRecordly || addScribe || addAgents || repairedRow {
                defaults.set(upgraded.encoded(), forKey: "topBar.tabs")
                defaults.set(TopBarLayout.knownEncoded(), forKey: "topBar.tabs.known")
            }
            if needsRepair { defaults.set(TopBarLayoutRepair.version, forKey: "topBar.layoutRepair") }
        }
        cuesEnabled = defaults.object(forKey: "topBar.cues") as? Bool ?? true
        liveMusicWings = defaults.object(forKey: "topBar.musicWings") as? Bool ?? true
        weatherCity = defaults.string(forKey: "topBar.weatherCity") ?? ""
        useCelsius = defaults.object(forKey: "topBar.celsius") as? Bool ?? (Locale.current.measurementSystem != .us)
        note = defaults.string(forKey: "topBar.note") ?? ""
        selectedModeKey = defaults.string(forKey: "dictation.mode") ?? "voice"
        script = defaults.string(forKey: "prompter.script") ?? Self.sampleScript
        roll = PrompterRoll(speed: defaults.object(forKey: "prompter.speed") as? Double ?? 32,
                            voiceFollow: defaults.object(forKey: "prompter.voice") as? Bool ?? true)
        prompterTextSize = defaults.object(forKey: "prompter.size") as? Double ?? 22
    }

    static let sampleScript = """
    # Opening
    Hi, I'm Tony. Thanks for taking the time today.
    I'll keep this short and show you what Zeus does.

    # Demo
    Watch the notch. It follows my voice, so when I stop talking, the words wait for me.

    # Close
    That's it. Questions?
    """

    func pasteScript() {
        if let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            script = text
        }
    }

    /// Jumps to the next cue below the reading line, or back to the first one at the end.
    func jumpToNextCue() {
        let positions = prompterCueOffsets.values.map(Double.init).sorted()
        guard let first = positions.first else { return }
        let next = positions.first { $0 > roll.offset + 4 } ?? first
        roll.jump(to: next)
    }

    // MARK: Derived

    var isDictating: Bool {
        switch dictationPhase {
        case .listening, .transcribing, .rewriting: true
        default: false
        }
    }

    /// Something worth showing beside the closed notch.
    var hasLiveActivity: Bool {
        isDictating || RecordlyController.shared.isRecording || cue != nil || (focus.phase != .idle && SettingsStore.shared.bool("lights.timer")) || (liveMusicWings && nowPlaying?.isPlaying == true)
    }

    var nextEvent: CalendarItem? {
        let now = Date()
        return events.first { !$0.isAllDay && $0.end > now }
    }

    var openReminders: [ReminderItem] { reminders.filter { !$0.done } }

    func temperature(_ celsius: Double) -> String {
        let value = useCelsius ? celsius : celsius * 9 / 5 + 32
        return "\(Int(value.rounded()))°"
    }

    // MARK: Cues

    func show(_ newCue: NotchCue) {
        FlightRecorder.shared.record("cue", Self.cueName(newCue))
        let essential: Bool
        switch newCue {
        case .dictation, .focusFinished, .usageAlert, .hint, .keepAwake: essential = true
        case .volume, .brightness, .keyboardBacklight: essential = true
        default: essential = false
        }
        let lightEnabled = Self.lightOption(for: newCue).map { SettingsStore.shared.bool($0) } ?? true
        guard lightEnabled else { return }
        // The macOS banner is a second presentation for an enabled cue, not a way to bypass
        // the cue's individual setting. Keep it independent of the notch-only `cuesEnabled` switch.
        if Self.systemNotificationAllowed(for: newCue, lightEnabled: lightEnabled) {
            onSystemNotification(newCue)
        }
        guard cuesEnabled || essential else { return }
        if case .focusFinished = newCue { ZeusSound.play(.timer) }
        cue = newCue
        cueStartedAt = Date()
        cueTask?.cancel()
        cueTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(newCue.duration))
            guard !Task.isCancelled else { return }
            self?.cue = nil
        }
    }

    /// The case name only (a copied text or track title stays out of the flight recorder).
    static func cueName(_ cue: NotchCue) -> String {
        String(String(describing: cue).prefix { $0 != "(" })
    }

    static func systemNotificationAllowed(for cue: NotchCue, lightEnabled: Bool) -> Bool {
        lightEnabled && SystemNotificationPayload.forCue(cue) != nil
    }

    /// Settings > Appearance > Everyday lights switch for each cue.
    static func lightOption(for cue: NotchCue) -> String? {
        switch cue {
        case .copied: "lights.copy"
        case .capsLock: "lights.capsLock"
        case .volume: SystemHUDSettings.settingID(for: .volume)
        case .charging, .lowBattery: "lights.battery"
        case .shelfAdded: "lights.shelf"
        case .brightness: SystemHUDSettings.settingID(for: .brightness)
        case .keyboardBacklight: SystemHUDSettings.settingID(for: .keyboardBacklight)
        case .shortcut: "lights.shortcutPeeks"
        case .rain: "lights.rain"
        case .screenshot: "lights.screenshot"
        default: nil
        }
    }

    /// Glance-style HUD: wings cue plus outline level glow; holds 1.2 s after the last change.
    /// H2/H3: continues the same light (springs from where the arm already was, not from zero)
    /// and adds a limit echo when the same direction hits 0 or 1 again.
    func presentSystemHUD(_ kind: SystemHUDKind, value: Double, muted: Bool, ignoreSettings: Bool = false) {
        let cue: NotchCue = switch kind {
        case .volume: .volume(value, muted: muted)
        case .brightness: .brightness(value)
        case .keyboardBacklight: .keyboardBacklight(value)
        }
        let previous = currentHUDLevel(for: kind)
        let atLowerBound = previous.seen && previous.value <= 0.001 && value <= previous.value
        let atUpperBound = previous.seen && previous.value >= 0.999 && value >= previous.value
        let light = NotchLightKind.hudLevel(
            kind, value: value, previousLevel: previous.seen ? previous.value : value,
            muted: muted, limitEcho: atLowerBound || atUpperBound)
        let spring = Animation.spring(
            response: NotchClosedBodyLayout.wingsSpringResponse,
            dampingFraction: NotchClosedBodyLayout.wingsSpringDamping)
        withAnimation(spring) {
            show(cue)
            flash(light, ignoreSettings: ignoreSettings)
        }
        ScreenEdgeGlowController.shared.present(kind: kind, value: value, muted: muted, ignoreSettings: ignoreSettings)
    }

    /// `zeus debug animate`: always draws notch lights and edge glow for QA screencapture.
    func presentSystemHUDForDebug(_ kind: SystemHUDKind, value: Double, muted: Bool) {
        presentSystemHUD(kind, value: value, muted: muted, ignoreSettings: true)
    }

    func flashForDebug(_ kind: NotchLightKind) {
        flash(kind, ignoreSettings: true)
    }

    /// The level of the currently-active `.hudLevel` light for `kind`, if any (used to spring
    /// from that level instead of zero on the next change, H2).
    private func currentHUDLevel(for kind: SystemHUDKind) -> (value: Double, seen: Bool) {
        for light in lights {
            if case .hudLevel(let k, let v, _, _, _) = light.kind, k == kind { return (v, true) }
        }
        return (0, false)
    }

    /// For snapshots: a cue frozen in place.
    func setCueForSnapshot(_ newCue: NotchCue?) {
        cue = newCue
        cueStartedAt = Date().addingTimeInterval(-0.6)
    }

    // MARK: Lights (closed notch outline and arms)

    struct ActiveLight: Identifiable, Equatable {
        let id: UUID
        let kind: NotchLightKind
        let startedAt: Date
        let duration: TimeInterval

        init(id: UUID = UUID(), kind: NotchLightKind, startedAt: Date, duration: TimeInterval? = nil) {
            self.id = id
            self.kind = kind
            self.startedAt = startedAt
            self.duration = duration ?? kind.duration
        }
    }
    private(set) var lights: [ActiveLight] = []
    /// Files are being dragged somewhere on screen: crests climb the arms.
    var isDraggingFiles = false
    /// The mic is listening for a spoken approval answer.
    var micListening = false
    var micLevel: Double = 0
    /// Recent dictation levels, newest last, for the live waveform.
    private(set) var dictationLevels: [Double] = Array(repeating: 0, count: 28)

    func pushDictationLevel(_ level: Double) {
        dictationLevel = level
        dictationLevels.removeFirst()
        dictationLevels.append(level)
    }

    /// Plays a light effect if its Settings switch is on. H2: a `.hudLevel` for a kind that's
    /// already lit updates that same light in place (same id, fresh deadline) instead of
    /// appending a second one, so repeated key presses continue one light, not several stacked.
    func flash(_ kind: NotchLightKind, ignoreSettings: Bool = false) {
        if !ignoreSettings, let option = Self.lightOption(for: kind), !SettingsStore.shared.bool(option) { return }
        // The screen-edge wave is a separate click-through overlay, not an outline light.
        if case .edgeWave(let tint) = kind {
            EdgeWaveController.shared.play(tint: tint, ignoreSettings: ignoreSettings)
            return
        }
        let duration = kind.duration(speedPercent: SettingsStore.shared.double("halo.speed"))
        if case .hudLevel(let newSystemKind, _, _, _, _) = kind,
           let index = lights.firstIndex(where: { if case .hudLevel(let k, _, _, _, _) = $0.kind { k == newSystemKind } else { false } }) {
            let id = lights[index].id
            lights[index] = ActiveLight(id: id, kind: kind, startedAt: Date(), duration: duration)
            scheduleRemoval(id: id, after: duration)
            return
        }
        let light = ActiveLight(kind: kind, startedAt: Date(), duration: duration)
        lights.append(light)
        scheduleRemoval(id: light.id, after: duration)
    }

    /// One removal per light: a refreshed light cancels the earlier timer, so the first deadline
    /// can't remove a light that was just extended.
    private var lightRemovals: [UUID: Task<Void, Never>] = [:]

    private func scheduleRemoval(id: UUID, after duration: TimeInterval) {
        lightRemovals[id]?.cancel()
        lightRemovals[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.05))
            guard !Task.isCancelled, let self else { return }
            self.lights.removeAll { $0.id == id }
            self.lightRemovals[id] = nil
        }
    }

    /// `zeus debug hud-state`: the current lights and cue as JSON, for QA when the notch is
    /// hidden from screen capture. `{"lights":[],"cue":null}` at idle.
    func hudStateJSON() -> String {
        struct LightInfo: Encodable { let kind: String; let age: Double }
        struct State: Encodable { let lights: [LightInfo]; let cue: String? }
        let now = Date()
        let infos = lights.map { LightInfo(kind: String(describing: $0.kind), age: now.timeIntervalSince($0.startedAt)) }
        let state = State(lights: infos, cue: cue.map { String(describing: $0) })
        guard let data = try? JSONEncoder().encode(state), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static func lightOption(for kind: NotchLightKind) -> String? {
        switch kind {
        case .copySweep: "lights.copy"
        case .capsLock, .shiftCrest: "lights.capsLock"
        case .battery: "lights.battery"
        case .landed(let airDrop): airDrop ? "lights.airDrop" : "lights.shelf"
        case .reminderPinned: "lights.reminderGlow"
        case .eventRibbon: "lights.eventGlow"
        case .shortcut: "lights.shortcutPeeks"
        case .entrance: nil
        case .edgeWave: "halo.edgeWave"
        case .hudLevel(let kind, _, _, _, _): SystemHUDSettings.settingID(for: kind)
        }
    }

    func setLightsForSnapshot(_ kinds: [(NotchLightKind, Double)]) {
        // A very long nominal duration pins the progress however long the render takes.
        lights = kinds.map { ActiveLight(kind: $0.0, startedAt: Date().addingTimeInterval(-1e6 * $0.1), duration: 1e6) }
    }

    // MARK: Shelf

    func addToShelf(_ urls: [URL], isAirDrop: Bool = false) {
        let fresh = urls.filter { url in !shelf.contains { $0.url == url } }
        guard !fresh.isEmpty else { return }
        shelf.insert(contentsOf: fresh.map { ShelfItem(url: $0) }, at: 0)
        show(.shelfAdded(fresh.count))
        flash(.landed(airDrop: isAirDrop))
    }

    func removeFromShelf(_ id: UUID) { shelf.removeAll { $0.id == id } }

    // MARK: Home customise

    func beginHomeCustomize() {
        guard selectedTab == .home else { return }
        homeCustomizing = true
        homePickerSlot = 1
    }

    func endHomeCustomize() {
        homeCustomizing = false
        homePickerSlot = nil
    }

    func setHomeWidget(slot: Int, to kind: HomeWidgetKind) {
        SettingsStore.shared.set(HomeSlots.settingID(slot: slot), kind.title)
    }

    func setHomeVariant(_ kind: HomeWidgetKind, to variant: HomeVariant) {
        SettingsStore.shared.set(kind.variantSettingID, variant.title)
    }

    func setHomeBackdrop(_ backdrop: HomeBackdrop) {
        SettingsStore.shared.set(HomeBackdrop.settingID, backdrop.title)
    }

    // MARK: Tab editor

    /// Starts from the row as it shows (a saved layout may list more tabs than fit).
    func beginTabEditing() {
        layout = layout.trimmedToRow()
        tabEditorNote = nil
        tabEditing = true
    }

    func endTabEditing() {
        tabEditing = false
        draggedTab = nil
        tabEditorNote = nil
    }

    func addTab(_ tab: TopBarTab) {
        guard !layout.contains(tab) else { return }
        if layout.isFull() {
            tabEditorNote = "The row holds \(GlanceTopBar.maxTabs) tabs. Remove one to add \(tab.title)."
            return
        }
        tabEditorNote = nil
        var next = layout
        next.append(tab)
        layout = next
    }

    func removeTab(_ tab: TopBarTab) {
        guard tab != .home, layout.contains(tab) else { return }
        tabEditorNote = nil
        var next = layout
        next.remove(tab)
        layout = next
        if selectedTab == tab { selectedTab = .home }
    }

    func moveTab(_ tab: TopBarTab, onto target: TopBarTab) {
        var next = layout
        next.reorder(tab, onto: target)
        if next != layout { layout = next }
    }

    // MARK: Calendar page

    func showMonth(offset: Int) {
        let calendar = ZeusDates.calendar()
        guard let month = calendar.date(byAdding: .month, value: offset, to: calendarMonth) else { return }
        calendarMonth = month
        calendarDetailID = nil
        refreshCalendarMonth()
    }

    func goToToday() {
        calendarMonth = Date()
        calendarDay = Date()
        calendarDetailID = nil
        refreshCalendarMonth()
    }

    func pickDay(_ day: Date) {
        calendarDay = day
        calendarDetailID = nil
    }

    /// The first and last day the month grid shows (whole weeks), and the events in them.
    func refreshCalendarMonth() {
        let range = CalendarGrid.visibleRange(month: calendarMonth, calendar: ZeusDates.calendar())
        calendarEvents = fetchEvents(range.lowerBound, range.upperBound)
    }

    func events(on day: Date) -> [CalendarItem] {
        let calendar = ZeusDates.calendar()
        return calendarEvents.filter { calendar.isDate($0.start, inSameDayAs: day) || ($0.start < day && $0.end > day && calendar.startOfDay(for: day) < $0.end) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    /// The quick-add field and the voice rule: read the words, save the event, light the ribbon.
    /// Returns what went wrong, if anything. Calendar access is asked for here and nowhere earlier.
    @discardableResult
    func addEvent(from text: String, now: Date = Date()) async -> String? {
        guard let parsed = CalendarQuickAdd.parse(text, now: now) else {
            quickAddNote = "Say what and when, like \"Lunch with Ana tomorrow at 1 pm\"."
            return quickAddNote
        }
        switch await createEvent(parsed) {
        case .created:
            eventCreated(parsed)
            return nil
        case .needsAccess:
            quickAddNote = "Calendar access is off. Turn it on in System Settings, Privacy & Security, Calendars."
            show(.permission("Zeus needs Calendar access to add events.", pane: "Privacy_Calendars"))
            return "I need Calendar access to add that."
        case .failed(let reason):
            quickAddNote = reason
            return reason
        }
    }

    /// An event Zeus made: the cyan ribbon (when `lights.eventGlow` is on), a note, and the page refreshes.
    func eventCreated(_ parsed: CalendarQuickAdd.Parsed) {
        flash(.eventRibbon)
        quickAddText = ""
        quickAddNote = "Added \(parsed.title), \(parsed.start.formatted(ZeusDates.style.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))."
        calendarDay = parsed.start
        calendarMonth = parsed.start
        refreshCalendarMonth()
    }
}
