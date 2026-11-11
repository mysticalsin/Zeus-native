import AppKit
import AVFoundation
import Carbon.HIToolbox
import Observation
import ZeusCore

/// A global shortcut picked from a short list, registered with Carbon so it works without Accessibility.
enum ShortcutPreset: String, CaseIterable, Identifiable {
    case off, controlOptionSpace, optionCommandZ, controlCommandZ, controlOptionT, optionCommandT

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .controlOptionSpace: "⌃⌥ Space"
        case .optionCommandZ: "⌥⌘ Z"
        case .controlCommandZ: "⌃⌘ Z"
        case .controlOptionT: "⌃⌥ T"
        case .optionCommandT: "⌥⌘ T"
        }
    }
    var keyCode: UInt32? {
        switch self {
        case .off: nil
        case .controlOptionSpace: UInt32(kVK_Space)
        case .optionCommandZ, .controlCommandZ: UInt32(kVK_ANSI_Z)
        case .controlOptionT, .optionCommandT: UInt32(kVK_ANSI_T)
        }
    }
    var modifiers: UInt32 {
        switch self {
        case .off: 0
        case .controlOptionSpace, .controlOptionT: UInt32(controlKey | optionKey)
        case .optionCommandZ, .optionCommandT: UInt32(optionKey | cmdKey)
        case .controlCommandZ: UInt32(controlKey | cmdKey)
        }
    }
}

/// Settings for notifications, sounds, shortcuts and interview privacy. Snapshots never write defaults.
@MainActor
@Observable
final class ExtraPreferences {
    static let shared = ExtraPreferences()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored var onShortcutsChange: (() -> Void)?

    private func store(_ value: Any, _ key: String) {
        if !TopBarStyle.isSnapshot { defaults.set(value, forKey: key) }
    }
    private static func bool(_ key: String, _ fallback: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }
    private static func int(_ key: String, _ fallback: Int) -> Int { UserDefaults.standard.object(forKey: key) as? Int ?? fallback }

    // Notifications: what peeks out of the notch.
    var peekApprovals = bool("notify.approvals", true) { didSet { store(peekApprovals, "notify.approvals") } }
    var peekAgentDone = bool("notify.agentDone", true) { didSet { store(peekAgentDone, "notify.agentDone") } }
    var calendarLeadMinutes = int("notify.calendarLead", 5) { didSet { store(calendarLeadMinutes, "notify.calendarLead") } }
    var peekReminders = bool("notify.reminders", true) { didSet { store(peekReminders, "notify.reminders") } }
    var peekFocusDone = bool("notify.focus", true) { didSet { store(peekFocusDone, "notify.focus") } }
    var quietWhileSharing = bool("notify.quietSharing", true) { didSet { store(quietWhileSharing, "notify.quietSharing") } }

    // Sounds.
    var soundsOn = bool("sound.on", true) { didSet { store(soundsOn, "sound.on") } }
    var soundVolume = int("sound.volume", 60) { didSet { store(soundVolume, "sound.volume") } }
    var soundApproval = bool("sound.approval", true) { didSet { store(soundApproval, "sound.approval") } }
    var soundDone = bool("sound.done", true) { didSet { store(soundDone, "sound.done") } }
    var soundTodo = bool("sound.todo", true) { didSet { store(soundTodo, "sound.todo") } }
    // Voice earcons: Zeus starts listening, stops listening, finished answering, or hit an error.
    var soundListenStart = bool("sound.voiceStart", true) { didSet { store(soundListenStart, "sound.voiceStart") } }
    var soundListenStop = bool("sound.voiceStop", true) { didSet { store(soundListenStop, "sound.voiceStop") } }
    var soundVoiceDone = bool("sound.voiceDone", true) { didSet { store(soundVoiceDone, "sound.voiceDone") } }
    var soundVoiceError = bool("sound.voiceError", true) { didSet { store(soundVoiceError, "sound.voiceError") } }

    // Shortcuts.
    var openNotch = ShortcutPreset(rawValue: UserDefaults.standard.string(forKey: "shortcut.openNotch") ?? "") ?? .optionCommandZ {
        didSet { store(openNotch.rawValue, "shortcut.openNotch"); onShortcutsChange?() }
    }
    var quickTodo = ShortcutPreset(rawValue: UserDefaults.standard.string(forKey: "shortcut.quickTodo") ?? "") ?? .controlOptionT {
        didSet { store(quickTodo.rawValue, "shortcut.quickTodo"); onShortcutsChange?() }
    }

    // Interview: keep every ZEUS window out of screen shares and recordings.
    var hideFromScreenShare = bool("interview.hide", false) { didSet { store(hideFromScreenShare, "interview.hide") } }

    /// Forgets the given keys, then reads every value again (section reset).
    func reset(_ keys: [String]) {
        if !TopBarStyle.isSnapshot { keys.forEach { defaults.removeObject(forKey: $0) } }
        if TopBarStyle.isSnapshot { return }
        reload()
    }

    /// Re-reads every value from defaults (after a reset or a settings import).
    func reload() {
        peekApprovals = Self.bool("notify.approvals", true)
        peekAgentDone = Self.bool("notify.agentDone", true)
        calendarLeadMinutes = Self.int("notify.calendarLead", 5)
        peekReminders = Self.bool("notify.reminders", true)
        peekFocusDone = Self.bool("notify.focus", true)
        quietWhileSharing = Self.bool("notify.quietSharing", true)
        soundsOn = Self.bool("sound.on", true)
        soundVolume = Self.int("sound.volume", 60)
        soundApproval = Self.bool("sound.approval", true)
        soundDone = Self.bool("sound.done", true)
        soundTodo = Self.bool("sound.todo", true)
        soundListenStart = Self.bool("sound.voiceStart", true)
        soundListenStop = Self.bool("sound.voiceStop", true)
        soundVoiceDone = Self.bool("sound.voiceDone", true)
        soundVoiceError = Self.bool("sound.voiceError", true)
        openNotch = ShortcutPreset(rawValue: defaults.string(forKey: "shortcut.openNotch") ?? "") ?? .optionCommandZ
        quickTodo = ShortcutPreset(rawValue: defaults.string(forKey: "shortcut.quickTodo") ?? "") ?? .controlOptionT
        hideFromScreenShare = Self.bool("interview.hide", false)
    }
}

/// Zeus's own synthesized sounds (Sources/Zeus/Sounds, made by tools/sounds/make_sounds.py) for each
/// event, at the chosen volume. Styles come from Settings > Sounds.
@MainActor
enum ZeusSound {
    enum Event: CaseIterable { case approval, done, todo, start, answer, timer, listenStart, listenStop, voiceDone, voiceError, failure, dictationBegin, dictationEnd
        /// The catalog option that picks this event's sound, if it has one.
        var styleOption: String? {
            switch self {
            case .approval: "sound.approvalStyle"
            case .done: "sound.doneStyle"
            case .start: "sound.startStyle"
            case .answer: "sound.answerStyle"
            default: nil
            }
        }
        var slot: SoundSlot {
            switch self {
            case .approval: .request
            case .done: .done
            case .start: .runStart
            case .answer: .answer
            case .todo: .todo
            case .timer: .timer
            case .listenStart: .listenStart
            case .listenStop: .listenStop
            case .voiceDone: .voiceDone
            case .voiceError: .voiceError
            case .failure: .failure
            case .dictationBegin: .dictationBegin
            case .dictationEnd: .dictationEnd
            }
        }
        /// The saved style for this event ("Off" is silence); nil for events with a single sound.
        @MainActor var name: String? { styleOption.map { SettingsStore.shared.string($0) } }
        var title: String {
            switch self {
            case .approval: "Needs you"
            case .done: "Agent done"
            case .todo: "To-do checked"
            case .start: "Run start"
            case .answer: "Your answer"
            case .timer: "Timer alarm"
            case .listenStart: "Zeus is listening"
            case .listenStop: "Zeus stopped listening"
            case .voiceDone: "Voice answer done"
            case .voiceError: "Voice error"
            case .failure: "Failure"
            case .dictationBegin: "Dictation begins"
            case .dictationEnd: "Dictation ends"
            }
        }
    }

    static func play(_ event: Event, force: Bool = false) {
        let prefs = ExtraPreferences.shared
        if !force {
            guard prefs.soundsOn, !MeetingState.active else { return }
            switch event {
            case .approval: guard prefs.soundApproval else { return }
            case .done: guard prefs.soundDone else { return }
            case .todo: guard prefs.soundTodo else { return }
            case .timer: guard SettingsStore.shared.bool("sound.timer") else { return }
            case .listenStart: guard prefs.soundListenStart else { return }
            case .listenStop: guard prefs.soundListenStop else { return }
            case .voiceDone: guard prefs.soundVoiceDone else { return }
            case .voiceError: guard prefs.soundVoiceError else { return }
            case .start, .answer, .failure, .dictationBegin, .dictationEnd: break
            }
        }
        play(slot: event.slot, style: event.name)
    }

    private static var players: [AVAudioPlayer] = []

    /// The bundled file for a slot and style; nil for "Off" or when the resource is missing.
    static func url(slot: SoundSlot, style: String?) -> URL? {
        guard let spec = SoundCatalog.spec(slot, style: style) else { return nil }
        let name = spec.fileName
        return ZeusResources.bundle?.resourceURL?.appendingPathComponent("Sounds/\(name)")
            ?? Bundle.main.resourceURL?.appendingPathComponent("Sounds/\(name)")
    }

    /// Plays one sound at the Settings volume. Previews use it too.
    @discardableResult
    static func play(slot: SoundSlot, style: String?, loops: Int = 0) -> AVAudioPlayer? {
        guard let url = url(slot: slot, style: style), let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        FlightRecorder.shared.record("sound", slot.rawValue, style ?? "")
        player.volume = Float(ExtraPreferences.shared.soundVolume) / 100
        player.numberOfLoops = loops
        players.removeAll { !$0.isPlaying }
        players.append(player)
        player.play()
        return player
    }

    private static var loop: AVAudioPlayer?
    /// The ambient running loop, held while an agent works and "Ambient loop" is on (AppDelegate.feedExtras).
    static func startRunningLoop() {
        guard loop?.isPlaying != true, ExtraPreferences.shared.soundsOn, !MeetingState.active else { return }
        loop = play(slot: .runningLoop, style: nil, loops: -1)
        loop?.volume = Float(ExtraPreferences.shared.soundVolume) / 100 * 0.5
    }
    static func stopRunningLoop() {
        guard let ending = loop else { return }
        loop = nil
        ending.setVolume(0, fadeDuration: 0.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ending.stop(); players.removeAll { $0 === ending } }
    }
}

/// Global shortcuts through Carbon's RegisterEventHotKey (no Accessibility grant needed).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false

    func set(_ bindings: [(ShortcutPreset, () -> Void)]) {
        set(raw: bindings.compactMap { preset, action in preset.keyCode.map { ($0, preset.modifiers, action) } })
    }

    /// Key code, Carbon modifiers and action; replaces every ZEUS hotkey.
    func set(raw bindings: [(UInt32, UInt32, () -> Void)]) {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []; actions = [:]
        installHandler()
        for (index, (code, modifiers, action)) in bindings.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x5A455553), id: id) // "ZEUS"
            if RegisterEventHotKey(code, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref); actions[id] = action
            }
        }
    }

    fileprivate func fire(_ id: UInt32) { actions[id]?() }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyCenter.shared.fire(id) } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// A redacted text block for bug reports: no keys, no home path, no file contents.
@MainActor
enum Diagnostics {
    static func lines(permissions: PermissionsModel?) -> [(String, String)] {
        let info = ProcessInfo.processInfo
        let socketUp = FileManager.default.fileExists(atPath: ZeusPaths.socket.path)
        var rows: [(String, String)] = [
            ("Zeus", ZeusCoreVersion.string),
            ("macOS", info.operatingSystemVersionString),
            ("Agent socket", socketUp ? "Listening" : "Not running"),
            ("Support folder", redact(ZeusPaths.supportDirectory.path)),
        ]
        if let permissions {
            rows.append(("Claude Code hooks", permissions.claudeHooksInstalled ? "Installed" : "Off"))
            rows.append(("Chrome bridge", permissions.chromeHostInstalled ? "Registered" : "Off"))
            for kind in PermissionsModel.Kind.allCases {
                rows.append((kind.rawValue, permissions.granted[kind] == true ? "On" : "Off"))
            }
        }
        return rows
    }

    static func report(permissions: PermissionsModel?) -> String {
        lines(permissions: permissions).map { "\($0.0): \($0.1)" }.joined(separator: "\n")
    }

    static func redact(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
