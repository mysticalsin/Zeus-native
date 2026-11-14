import AppKit
import ApplicationServices
import ZeusCore

/// Turns NSEvent flags into the portable modifier set.
extension ShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var mods: ShortcutModifiers = []
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.function) { mods.insert(.function) }
        self = mods
    }
}

/// Whether ZEUS may see keys typed in other apps: Accessibility or Input Monitoring.
@MainActor
enum KeyListenAccess {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var inputMonitoring: Bool { CGPreflightListenEventAccess() }
    static var granted: Bool { accessibility || inputMonitoring }
    private static var waiting: [() -> Void] = []
    private static var timer: Timer?

    /// Runs `work` as soon as either is on, polling every 3 s (never a prompt).
    static func whenGranted(_ work: @escaping () -> Void) {
        if granted { work(); return }
        waiting.append(work)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard granted else { return }
                timer?.invalidate(); timer = nil
                let ready = waiting; waiting.removeAll()
                VoiceLog.log("keys", "access granted, starting \(ready.count) key monitors")
                ready.forEach { $0() }
            }
        }
    }

    /// Raises the Input Monitoring prompt (once ever per build identity) or opens its pane.
    static func requestInputMonitoring() {
        if !CGPreflightListenEventAccess(), !CGRequestListenEventAccess() { openInputMonitoring() }
    }

    static func openInputMonitoring() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
    }
}

/// What to tell the user when Zeus can't see keys outside its own windows (QA gate, 2 Nov 22:50:
/// a stale TCC grant pointing at an old build looks exactly like this, and a log line alone is
/// invisible to them). Pure so the message and startup check are unit-testable.
enum KeyAccessNotice {
    static func cue(granted: Bool) -> (text: String, pane: String)? {
        granted ? nil : ("Hold-to-talk and dictation need Accessibility or Input Monitoring.", "Privacy_Accessibility")
    }
}

/// The adapter of the voice key machine (`VoiceKeyMachine`, docs/VOICE-KEY-MACHINE-PLAN.md): it turns keyboard events,
/// keys the tiling tap consumed and timer firings into machine events and runs the effects that come back. It keeps no
/// state of its own: after `start()` only `machine` changes. Modifier chords, single modifiers (Right Command, Fn) and
/// keys with modifiers (Option-Space) are read from the event stream by the machine. Global monitoring needs
/// Accessibility or Input Monitoring; the local monitor covers Zeus's own windows.
@MainActor
final class HotkeyMonitor {
    /// A press the machine starts a turn for. Answers whether the owner took it: false (a transcribing job, a failed
    /// start) tells the machine the turn never opened, so no release or cancel follows.
    var onPress: (() -> Bool)?
    var onRelease: (() -> Void)?
    /// Called when the key is held but can't be used (Control+Option while VoiceOver is on).
    var onBlocked: ((String) -> Void)?
    /// A turn the key ended without sending it: a shortcut or a larger chord took the press over.
    var onCancel: (() -> Void)?
    /// Which shortcut this monitor listens for; nil turns it off. Push-to-talk by default (moved off
    /// Control+Option while VoiceOver uses it, `VoiceKey.effectiveTalkKey`); dictation supplies its own.
    var keyProvider: () -> Shortcut? = {
        let dictation = DictationSettings.shared
        return VoiceKey.effectiveTalkKey(chosen: Preferences.shared.pushToTalk,
                                         dictation: dictation.enabled ? dictation.key : nil,
                                         pointing: PointingSettings.enabled ? PointingSettings.shortcut : nil,
                                         voiceOverOn: NSWorkspace.shared.isVoiceOverEnabled)
    }
    /// Dedicated dictation keys can toggle on each press instead of holding. Shared keys never toggle.
    var directPressProvider: () -> Bool = { false }
    /// When talk and dictation share one key, each monitor reacts to its own gesture of it:
    /// dictation to a hold, talk (command mode) to a double-tap.
    enum Role { case talk, dictation }
    var role: Role = .talk
    var sharedProvider: () -> Bool = { DictationSettings.shared.enabled && Preferences.shared.pushToTalk == DictationSettings.shared.key }
    var voiceOverProvider: () -> Bool = { NSWorkspace.shared.isVoiceOverEnabled }
    /// How long a hold key must be down alone before it acts: 0 unless a tiling chord holds its modifiers.
    var confirmProvider: () -> TimeInterval = { 0 }
    /// The modifiers the system reports right now, to find a release no event told the machine about.
    var liveModifiers: () -> ShortcutModifiers? = {
        ShortcutModifiers(NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask))
    }
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    private var keyMonitors: [Any] = []
    private var consumedKeys: NSObjectProtocol?
    private var machine = VoiceKeyMachine()

    /// Keys the tiling tap consumes never reach the event monitors; the tap posts each one as the event a monitor would
    /// have seen. It goes through the same `feed` as the monitors' own events, so a consumed key and the same key
    /// unconsumed give the same callbacks. Idempotent.
    func observeConsumedKeys() {
        guard consumedKeys == nil else { return }
        consumedKeys = NotificationCenter.default.addObserver(
            forName: TilingConsumedKey.notification, object: nil, queue: .main) { [weak self] note in
            guard let event = TilingConsumedKey.event(in: note) else { return }
            MainActor.assumeIsolated { self?.feed(event) }
        }
    }

    func start() {
        observeConsumedKeys()
        KeyListenAccess.whenGranted { [weak self] in self?.startGlobal() }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp], handler: { [weak self] event in
            let converted = Self.convert(event)
            MainActor.assumeIsolated { if let converted { self?.feed(converted) } }
            return event
        }) { keyMonitors.append(local) }
    }

    /// Global monitors only once access is on, so macOS never prompts mid-use.
    private func startGlobal() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp], handler: { [weak self] event in
            let converted = Self.convert(event)
            MainActor.assumeIsolated { if let converted { self?.feed(converted) } }
        }) { keyMonitors.append(global) }
    }

    private static func convert(_ event: NSEvent) -> ShortcutEvent? {
        let mods = ShortcutModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        switch event.type {
        case .flagsChanged: return .flags(keyCode: event.keyCode, modifiers: mods)
        case .keyDown: return event.isARepeat ? nil : .keyDown(keyCode: event.keyCode, modifiers: mods)
        case .keyUp: return .keyUp(keyCode: event.keyCode)
        default: return nil
        }
    }

    // MARK: Entries

    /// One keyboard event from either monitor or from the consumed key feed (also the entry point for tests).
    func feed(_ event: ShortcutEvent) { send(.key(event, at: now())) }

    /// The owner's turn stopped listening for a reason of its own (Esc, a failed start): the machine forgets it.
    func turnEnded() { send(.abandon) }

    /// Sleep or wake: an open turn is cancelled, and nothing begins until every key is up.
    func interrupt() { send(.interrupt(live: liveModifiers())) }

    private func tick() { send(.tick(at: now(), live: liveModifiers())) }

    // MARK: Effects

    private var config: VoiceKeyMachine.Config {
        let key = keyProvider()
        let shared = sharedProvider()
        let toggle = role == .dictation && !shared && directPressProvider()
        return VoiceKeyMachine.Config(key: key,
                                      role: role == .talk ? .talk : .dictation,
                                      mode: shared ? .shared : toggle ? .toggle : .hold,
                                      voiceOverHoldsKey: key == .controlOption && voiceOverProvider(),
                                      confirm: confirmProvider())
    }

    /// The effects of one event run in order after the machine has handled it, so an owner that calls `turnEnded()` from
    /// inside a callback meets the machine in its new state.
    private func send(_ event: VoiceKeyMachine.Event) {
        let config = config
        for effect in machine.handle(event, config: config) {
            switch effect {
            case .start:
                VoiceLog.log("key", "\(role == .talk ? "talk" : "dictation") shortcut down (\(config.key?.title ?? "none"))")
                if onPress?() == false { send(.abandon) }
            case .send:
                onRelease?()
            case .cancel:
                VoiceLog.log("key", "\(role == .talk ? "talk" : "dictation") shortcut became another shortcut: cancelled, nothing sent")
                onCancel?()
            case .refused:
                onBlocked?("VoiceOver is using Control and Option. Record another shortcut in ZEUS Settings.")
            case .wake(let after):
                DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
                    MainActor.assumeIsolated { self?.tick() }
                }
            }
        }
    }
}
