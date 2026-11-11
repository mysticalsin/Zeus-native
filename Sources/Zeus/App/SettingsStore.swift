import AppKit
import AVFoundation
import CoreAudio
import CoreLocation
import EventKit
import Observation
import ServiceManagement
import SwiftUI
import ZeusCore

/// One option in the catalog (`SettingsCatalog.all`, generated from the Glance inventory table).
struct SettingOption: Identifiable, Sendable {
    enum Kind: Sendable { case toggle, choice, slider, text, action, status }
    /// live: wired here. custom: a hand-built row elsewhere on the page. stub: stored and exported, labelled "Coming".
    enum State: Sendable { case live, custom, stub }
    struct Range: Sendable { let min: Double; let max: Double; let step: Double }

    let id: String
    let section: SettingsNavigation.Section
    let group: String
    let title: String
    let note: String
    let kind: Kind
    let choices: [String]
    let range: Range?
    let defaultValue: String
    let state: State
    let todo: String

    /// Words the sidebar search matches.
    var haystack: String { [title, note, group, section.title, todo].joined(separator: " ").lowercased() }

    /// Unfinished options stay stored and exported but never show, in any section.
    var isShown: Bool { state != .stub }
}

extension SettingsCatalog {
    static func option(_ id: String) -> SettingOption? { all.first { $0.id == id } }
    static func options(in section: SettingsNavigation.Section) -> [SettingOption] { all.filter { $0.section == section && $0.isShown } }

    /// Every hit for a sidebar query: each word must appear somewhere in the option.
    static func search(_ query: String) -> [SettingOption] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return all.filter { option in option.isShown && words.allSatisfy { option.haystack.contains($0) } }
    }
}

/// Values for catalog options, saved as `opt.<id>` strings. Snapshots never write defaults.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private(set) var values: [String: String] = [:]
    /// Extra status text the app fills in (agents, sockets); read by status rows.
    var statusOverrides: [String: (Bool, String)] = [:]
    @ObservationIgnored var onChange: ((String) -> Void)?
    @ObservationIgnored var actions: [String: @MainActor () -> Void] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    static func key(_ id: String) -> String { "opt." + id }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `topBar.halo` (what the notch read) and `halo.style` (what the picker wrote) are one setting now.
        if !TopBarStyle.isSnapshot {
            HaloMigration.run(defaults: defaults)
            SystemHUDMigration.run(defaults: defaults)
            ScreenShareMigration.run(defaults: defaults)
        }
        for option in SettingsCatalog.all where option.state != .custom {
            values[option.id] = defaults.string(forKey: Self.key(option.id)) ?? option.defaultValue
        }
        // Show what macOS has registered, not the stored default. Nothing is registered here.
        if !TopBarStyle.isSnapshot, LaunchAtLogin.isBundled {
            values[Self.launchAtLoginID] = LaunchAtLogin.isOn ? "true" : "false"
        }
    }

    static let launchAtLoginID = "general.launchAtLogin"

    func string(_ id: String) -> String { values[id] ?? defaults.string(forKey: Self.key(id)) ?? SettingsCatalog.option(id)?.defaultValue ?? "" }
    func bool(_ id: String) -> Bool { string(id) == "true" }
    /// Never NaN, infinite or beyond a billion, so `Int(store.double(...))` cannot trap on a hand-edited value.
    func double(_ id: String) -> Double {
        let value = Double(string(id)) ?? 0
        return value.isFinite ? min(max(value, -1_000_000_000), 1_000_000_000) : 0
    }
    func words(_ id: String) -> [String] {
        string(id).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    func set(_ id: String, _ value: String) {
        guard values[id] != value else { return }
        values[id] = value
        if !TopBarStyle.isSnapshot { defaults.set(value, forKey: Self.key(id)) }
        onChange?(id)
    }

    func boolBinding(_ id: String) -> Binding<Bool> {
        if id == Self.launchAtLoginID, !TopBarStyle.isSnapshot, LaunchAtLogin.isBundled {
            // Reads the real SMAppService state and drives it; a refused change shows an alert and the switch stays put.
            return Binding(get: { LaunchAtLogin.isOn }, set: { on in self.applyLaunchAtLogin(on) })
        }
        return Binding(get: { self.bool(id) }, set: { self.set(id, $0 ? "true" : "false") })
    }

    private func applyLaunchAtLogin(_ on: Bool) {
        let problem = LaunchAtLogin.set(on)
        // Store what macOS now says. Changing the stored value makes the switch redraw.
        let actual = LaunchAtLogin.isOn
        values[Self.launchAtLoginID] = actual ? "true" : "false"
        defaults.set(actual ? "true" : "false", forKey: Self.key(Self.launchAtLoginID))
        if let problem {
            let alert = NSAlert()
            alert.messageText = "Launch at login"
            alert.informativeText = problem
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    func stringBinding(_ id: String) -> Binding<String> {
        Binding(get: { self.string(id) }, set: { self.set(id, $0) })
    }

    // MARK: Reset

    /// Hand-built rows that live in ExtraPreferences, by section, so a section reset covers them too.
    static let extraKeys: [SettingsNavigation.Section: [String]] = [
        .notifications: ["notify.approvals", "notify.agentDone", "notify.calendarLead", "notify.reminders", "notify.focus", "notify.quietSharing"],
        .sounds: ["sound.on", "sound.volume", "sound.approval", "sound.done", "sound.todo", "sound.voiceStart", "sound.voiceStop", "sound.voiceDone", "sound.voiceError"],
        .shortcuts: ["shortcut.openNotch", "shortcut.quickTodo"],
        .interview: ["interview.hide"],
    ]

    func resettable(_ section: SettingsNavigation.Section) -> Bool {
        Self.extraKeys[section] != nil || SettingsCatalog.options(in: section).contains { $0.state != .custom && Self.isValue($0.kind) }
    }

    func reset(_ section: SettingsNavigation.Section) {
        for option in SettingsCatalog.options(in: section) where option.state != .custom && Self.isValue(option.kind) {
            set(option.id, option.defaultValue)
        }
        if let keys = Self.extraKeys[section] { ExtraPreferences.shared.reset(keys) }
    }

    private static func isValue(_ kind: SettingOption.Kind) -> Bool { kind != .action && kind != .status }

    // MARK: Import and export

    /// How an imported value for a stored ZEUS key is checked before it is applied.
    enum AppRule {
        case bool
        case text(Int)
        case number(ClosedRange<Double>)
        /// A string or a finite number, for keys whose storage type another file owns.
        case scalar
        /// A whole number (no fraction) in the range.
        case whole(ClosedRange<Int>)
        /// A string that names a case of an app enum.
        case named(@Sendable (String) -> Bool)

        func accepts(_ value: Any) -> Bool {
            switch self {
            case .whole(let range):
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
                let double = number.doubleValue
                guard double.isFinite, double == double.rounded(), abs(double) < 1e9 else { return false }
                return range.contains(Int(double))
            case .named(let isValid):
                guard let text = value as? String, text.count <= 200 else { return false }
                return isValid(text)
            case .bool:
                guard let number = value as? NSNumber else { return false }
                return CFGetTypeID(number) == CFBooleanGetTypeID()
            case .text(let limit):
                guard let text = value as? String else { return false }
                return text.count <= limit
            case .number(let range):
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
                return number.doubleValue.isFinite && range.contains(number.doubleValue)
            case .scalar:
                if let text = value as? String { return text.count <= 200 }
                guard let number = value as? NSNumber else { return false }
                return number.doubleValue.isFinite
            }
        }
    }

    private static let boolKeys = [
        "notify.approvals", "notify.agentDone", "notify.reminders", "notify.focus", "notify.quietSharing",
        "sound.on", "sound.approval", "sound.done", "sound.todo", "sound.voiceStart", "sound.voiceStop", "sound.voiceDone", "sound.voiceError",
        "interview.hide", "avatar.alwaysInNotch", "showCaptions", "showMenuBarIcon",
        "topBar.cues", "topBar.musicWings", "topBar.celsius",
        "dictation.enabled", "dictation.autoSwitch", "dictation.pauseMedia", "dictation.restoreClipboard", "dictation.sounds",
        "dictation.preview", "dictation.engineForVoice", "dictation.alwaysType",
        "prompter.voice",
    ]

    // Left out of an export on purpose: `dictation.typedApps` (a list, and the apps differ per Mac),
    // `voice.engine` (it only counts once confirmed on this Mac, see `voice.engine.userSelected`), the voice
    // pause timers, and every key, which lives in the Keychain. An import never selects a cloud engine or
    // voice (`importWouldSelectCloud`), since this Mac may already hold that service's key.

    private static let otherRules: [String: AppRule] = [
        "notify.calendarLead": .number(0...180),
        "sound.volume": .number(0...100),
        "shortcut.openNotch": .text(40), "shortcut.quickTodo": .text(40),
        "pushToTalk": .scalar, "talk.shortcut": .scalar, "dictation.shortcut": .scalar, "dictation.key": .scalar,
        "topBar.tabs": .text(2000), "topBar.tabs.known": .text(2000), "topBar.weatherCity": .text(120),
        // 0 is "Forever", so it must survive an export and import.
        "dictation.mode": .text(64), "dictation.keepDays": .whole(0...3650),
        // The keys the dictation and voice models really write (DictationSettings, VoiceSettings).
        "dictation.language": .text(64),
        "dictation.engine": .named { TranscriptionEngineKind(rawValue: $0) != nil },
        "dictation.behavior": .named { DictationBehavior(rawValue: $0) != nil },
        "dictation.microphone": .text(200),
        "voice.ttsProvider": .named { VoiceTTSProvider(rawValue: $0) != nil },
        "voice.kokoro.voice": .text(64), "voice.kokoro.speed": .number(0.25...4),
        "prompter.size": .number(8...120), "prompter.speed": .number(1...300),
        "code.tool": .text(64), "code.terminal": .text(64),
    ]

    /// Every stored ZEUS key an export carries, each with the check an import applies. Never secrets: keys live in the keychain.
    static let appRules: [String: AppRule] = {
        var rules = otherRules
        for key in boolKeys { rules[key] = .bool }
        // Privacy and control switches the Settings pages own (they are not `opt.` values).
        rules[CLIAccess.defaultsKey] = .bool
        rules[WakeWordController.defaultsKey] = .bool
        rules[DriveAutonomy.settingsKey] = .text(64)
        return rules
    }()

    static var appKeys: [String] { appRules.keys.sorted() }

    /// Switches an imported file may leave alone or turn off, never on: they open the microphone, send data or
    /// loosen what Zeus may do. A person turns these on, on the Mac they are using.
    static let neverEnabledByImport: Set<String> = [
        "voice.answers", "privacy.lyrics", "lights.liveSpectrum", "lights.shortcutPeeks", "present.physicalPointer",
        "notify.system", "notify.replaceBanners", "general.showInScreenSharing", "lights.airDrop", "lights.screenshot", "about.autoUpdate",
    ]
    private static var neverEnabledAppKeys: Set<String> {
        [CLIAccess.defaultsKey, WakeWordController.defaultsKey, "dictation.engineForVoice"]
    }
    /// A cloud transcription engine or a non-local voice provider is only ever chosen on this Mac, by hand.
    static func importWouldSelectCloud(key: String, value: Any) -> Bool {
        guard let raw = value as? String else { return false }
        switch key {
        case "dictation.engine": return TranscriptionEngineKind(rawValue: raw)?.isCloud ?? false
        case "voice.ttsProvider": return VoiceTTSProvider(rawValue: raw).map { $0 != .kokoro && $0 != .chatterbox } ?? false
        default: return false
        }
    }
    /// Decided on each Mac, never carried over: how far Zeus may drive.
    private static var neverImportedAppKeys: Set<String> { [DriveAutonomy.settingsKey] }

    /// Whether an exported option value fits its option: a switch holds true or false, a choice is one of its
    /// choices, a slider is a finite number in its range.
    static func accepts(_ value: String, for option: SettingOption) -> Bool {
        switch option.kind {
        case .toggle: return value == "true" || value == "false"
        case .choice: return option.choices.contains(value)
        case .slider:
            guard let range = option.range, let number = Double(value), number.isFinite else { return false }
            return range.min <= number && number <= range.max
        case .text: return value.count <= 4096
        case .action, .status: return false
        }
    }

    func exportJSON() throws -> Data {
        var app: [String: Any] = [:]
        for key in Self.appKeys {
            if let value = defaults.object(forKey: key), value is String || value is NSNumber { app[key] = value }
        }
        var optionValues = values
        for option in SettingsCatalog.all where option.state == .custom {
            if let value = defaults.string(forKey: Self.key(option.id)) { optionValues[option.id] = value }
        }
        let root: [String: Any] = ["format": "zeus.settings", "version": 1, "options": optionValues, "app": app]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// Applies a file from `exportJSON`; returns how many values changed. Unknown keys, wrong types, unlisted
    /// choices, out-of-range numbers and privacy switches that would turn on are left out; everything is
    /// checked before anything is applied.
    @discardableResult
    func importJSON(_ data: Data) throws -> Int {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["format"] as? String == "zeus.settings", root["version"] as? Int == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var optionChanges: [(id: String, value: String)] = []
        for (id, raw) in root["options"] as? [String: Any] ?? [:] {
            guard let option = SettingsCatalog.option(id), option.state != .stub, let value = raw as? String,
                  Self.accepts(value, for: option) else { continue }
            if option.kind == .toggle, value == "true", Self.neverEnabledByImport.contains(id) { continue }
            if values[id] != value { optionChanges.append((id, value)) }
        }
        var appChanges: [(key: String, value: Any)] = []
        for (key, value) in root["app"] as? [String: Any] ?? [:] {
            let rule = Self.appRules[key] ?? (key == HaloMigration.legacyKey ? AppRule.text(64) : nil)
            guard let rule, rule.accepts(value), !Self.neverImportedAppKeys.contains(key) else { continue }
            if Self.neverEnabledAppKeys.contains(key), (value as? NSNumber)?.boolValue == true { continue }
            // An import never moves speech to a cloud service: this Mac may already hold that service's key.
            if Self.importWouldSelectCloud(key: key, value: value) { continue }
            appChanges.append((key, value))
        }
        for change in optionChanges { set(change.id, change.value) }
        for change in appChanges where !TopBarStyle.isSnapshot { defaults.set(change.value, forKey: change.key) }
        if !TopBarStyle.isSnapshot, let style = HaloMigration.run(defaults: defaults) { values["halo.style"] = style.rawValue }
        ExtraPreferences.shared.reload()
        return optionChanges.count + appChanges.count
    }
}

// MARK: Live behaviour behind catalog options

/// Meeting mode: another app holds the microphone, or the display is mirrored for a projector.
@MainActor
enum MeetingState {
    private(set) static var active = false

    static func refresh(ownMicInUse: Bool) {
        guard SettingsStore.shared.bool("general.meetingMode"), !TopBarStyle.isSnapshot else { active = false; return }
        active = (!ownMicInUse && micInUseSomewhere()) || displayMirrored()
    }

    /// Hide commands and project names on cards when asked, or while a meeting is on.
    static var hideDetails: Bool { !SettingsStore.shared.bool("privacy.details") || active }

    private static func micInUseSomewhere() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return false }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    private static func displayMirrored() -> Bool {
        NSScreen.screens.contains { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsInMirrorSet(id) != 0
        }
    }
}

/// Launch at login through SMAppService. Only a bundled .app can register.
@MainActor
enum LaunchAtLogin {
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    static var isOn: Bool { isBundled && SMAppService.mainApp.status == .enabled }

    /// Why the last register or unregister did not end as asked; nil when it did.
    private(set) static var lastError: String?

    /// Registers or unregisters, then returns nil on success or a message to show.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        guard isBundled, !TopBarStyle.isSnapshot else { return nil }
        let service = SMAppService.mainApp
        do {
            if on {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            lastError = "Zeus couldn't \(on ? "turn on" : "turn off") launch at login: \(error.localizedDescription)"
            return lastError
        }
        if on, service.status == .requiresApproval {
            lastError = "Allow Zeus in System Settings › General › Login Items to launch it at login."
        } else {
            lastError = nil
        }
        return lastError
    }
}

/// Status rows: permissions macOS reports, plus the facts ZEUS knows about itself.
@MainActor
enum SettingStatus {
    static func value(_ id: String) -> (Bool, String) {
        if let override = SettingsStore.shared.statusOverrides[id] { return override }
        if TopBarStyle.isSnapshot { return snapshot(id) }
        switch id {
        case "perm.location":
            let status = CLLocationManager().authorizationStatus
            return status == .authorizedAlways ? (true, "Allowed") : (false, status == .denied ? "Denied" : "Optional")
        case "perm.calendar": return eventKit(.event)
        case "perm.reminders": return eventKit(.reminder)
        case "perm.notifications": return (false, "Not used yet")
        case "perm.fullDisk":
            let probe = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/Bookmarks.plist")
            return FileHandle(forReadingAtPath: probe.path) != nil ? (true, "Allowed") : (false, "Not needed yet")
        case "perm.automation": return (true, "Asked per app")
        case "dictation.model": return (true, "Apple on-device · no download")
        case "integrations.codex":
            let cliFound = CLILocator.tools.first { $0.name == "codex" }.flatMap(CLILocator.locate) != nil
            return codexConnectionStatus(cliFound: cliFound, hookInstalled: AgentHookInstaller.isInstalled(.codex))
        case "integrations.antigravity":
            let found = ["/Applications/Antigravity.app", NSHomeDirectory() + "/Applications/Antigravity.app"].contains { FileManager.default.fileExists(atPath: $0) }
            return found ? (true, "App found") : (false, "Not installed")
        case "privacy.analytics": return (true, "Off · Zeus sends nothing")
        case "interview.key": return (true, "Not needed")
        case "perm.trustedChats": return (false, "None")
        default: return (false, "Coming")
        }
    }

    static func codexConnectionStatus(cliFound: Bool, hookInstalled: Bool) -> (Bool, String) {
        if hookInstalled { return (true, "Hook installed · approvals") }
        if cliFound { return (true, "Logs only · hook adds approvals") }
        return (false, "Not installed")
    }

    private static func eventKit(_ type: EKEntityType) -> (Bool, String) {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: (true, "Allowed")
        case .writeOnly: (true, "Add only")
        case .denied, .restricted: (false, "Denied")
        default: (false, "Not asked")
        }
    }

    private static func snapshot(_ id: String) -> (Bool, String) {
        switch id {
        case "perm.location": (false, "Optional")
        case "perm.calendar", "perm.reminders": (true, "Allowed")
        case "perm.notifications": (false, "Not used yet")
        case "perm.fullDisk": (false, "Not needed yet")
        case "perm.automation": (true, "Asked per app")
        case "dictation.model": (true, "Apple on-device · no download")
        case "integrations.codex": codexConnectionStatus(cliFound: true, hookInstalled: false)
        case "integrations.antigravity": (false, "Not installed")
        case "privacy.analytics": (true, "Off · Zeus sends nothing")
        case "interview.key": (true, "Not needed")
        case "diag.agents": (true, "Claude Code · 2 sessions")
        case "perm.trustedChats": (false, "None")
        default: (false, "Coming")
        }
    }
}
