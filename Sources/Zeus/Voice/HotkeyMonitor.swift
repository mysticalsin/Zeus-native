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

/// The hardware's own answer to which of these ordinary keys are down. The hardware state is not the event stream a
/// secure input field withholds, and a key the tiling tap consumed is still a key that is down.
func ordinaryKeysDownInTheSystem(_ codes: Set<UInt16>) -> Set<UInt16> {
    codes.filter { CGEventSource.keyState(.hidSystemState, key: CGKeyCode($0)) }
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
/// state of its own: after `start()` only `pair` changes, the machine of the talk key and of the second talk key behind one
/// arbiter (`TalkKeyPair`; with no second key it is the machine). Modifier chords, single modifiers (Right Command, Fn) and
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
    /// How long a hold key must be down alone before it acts, when the owner sets its own. Nil asks tiling.
    var confirmProvider: (() -> TimeInterval)?
    /// What tiling says a hold key must wait: 0 unless the tap is installed and a bound chord holds the key's modifiers.
    static var tilingConfirm: (Shortcut) -> TimeInterval = { TilingController.shared.holdConfirm(for: $0) }
    /// The code of the key that may join this hold without spoiling it (Space on Control-Option, the talk chord), nil for
    /// none. Only the talk role reads it, and only in hold mode.
    var chordProvider: () -> UInt16? = { nil }
    /// The second talk key (Right Option unless the owner chose another key or turned it off), nil for none. Only the talk role
    /// reads it, and it is read on every event, so the owner hands back a value its sync points stored (docs/RIGHT-OPTION-TALK-PLAN.md).
    var secondKeyProvider: () -> Shortcut? = { nil }
    /// The modifiers the system reports right now, to find a release no event told the machine about.
    var liveModifiers: () -> ShortcutModifiers? = {
        ShortcutModifiers(NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask))
    }
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// Of these ordinary keys, the ones the system reports down now. Nil until `start()` asks the keyboard itself, so a
    /// test that feeds keys with no key-up is not undone by the real keyboard.
    var keysStillDown: ((Set<UInt16>) -> Set<UInt16>)?

    private var keyMonitors: [Any] = []
    private var consumedKeys: NSObjectProtocol?
    private var sleepObservers: [NSObjectProtocol] = []
    private var pair = TalkKeyPair()
    /// The number the machine gave the last turn that `onPress` was asked to start, 0 before the first.
    private var ownerTurn = 0

    /// Keys the tiling tap consumes never reach the event monitors; the tap posts each one as the event a monitor would
    /// have seen. It goes through the same `feed` as the monitors' own events, so a consumed key and the same key
    /// unconsumed give the same callbacks. Idempotent.
    func observeConsumedKeys() {
        guard consumedKeys == nil else { return }
        consumedKeys = NotificationCenter.default.addObserver(
            forName: TilingConsumedKey.notification, object: nil, queue: .main) { [weak self] note in
            guard let event = TilingConsumedKey.event(in: note) else { return }
            let time = TilingConsumedKey.timestamp(in: note)
            MainActor.assumeIsolated { self?.feed(event, at: time) }
        }
    }

    func start() {
        if keysStillDown == nil { keysStillDown = ordinaryKeysDownInTheSystem }
        observeConsumedKeys()
        observeSleep()
        KeyListenAccess.whenGranted { [weak self] in self?.startGlobal() }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp], handler: { [weak self] event in
            let converted = Self.convert(event)
            let time = event.timestamp
            MainActor.assumeIsolated { if let converted { self?.feed(converted, at: time) } }
            return event
        }) { keyMonitors.append(local) }
        if let localMouse = NSEvent.addLocalMonitorForEvents(matching: Self.mouseDowns, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseDown() }
            return event
        }) { keyMonitors.append(localMouse) }
    }

    private static let mouseDowns: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

    /// Global monitors only once access is on, so macOS never prompts mid-use.
    private func startGlobal() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp], handler: { [weak self] event in
            let converted = Self.convert(event)
            let time = event.timestamp
            MainActor.assumeIsolated { if let converted { self?.feed(converted, at: time) } }
        }) { keyMonitors.append(global) }
        if let globalMouse = NSEvent.addGlobalMonitorForEvents(matching: Self.mouseDowns, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }) { keyMonitors.append(globalMouse) }
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

    /// One keyboard event from either monitor or from the consumed key feed (also the entry point for tests). `time` is
    /// when the key went down or up, on the clock of `now`: the machine reads a key at its own time, because a busy main
    /// thread hears it later and a timer that came due in between must not be judged by that delay. Without one, or with
    /// a zero, the event is taken as it arrives, and a time still to come is read as now. A key-up no monitor saw would leave its key in the
    /// picture as a foreign key, so while the picture holds any ordinary key the system is asked first which of them
    /// are still down.
    func feed(_ event: ShortcutEvent, at time: TimeInterval? = nil) {
        let held = pair.keys.keysDown
        if !held.isEmpty, let keysStillDown { send(.sweep(live: keysStillDown(held))) }
        let arrived = now()
        let at = time.map { $0 > 0 ? min($0, arrived) : arrived } ?? arrived
        // The talk chord's Space may be held by Carbon, which hides its key-down from the monitors. On a flags event the
        // system is asked about it, and the machine hears the key-down it missed, on the flags it had before this event, so
        // a Space that came before the set spoils the hold and a Space that joined the set does not. It is read at the time
        // of the flags event, not the time that event is heard: a busy main thread must not make a short tap stand for the
        // confirm.
        if case .flags = event, let chord = chordProvider(), !pair.keys.keysDown.contains(chord),
           keysStillDown?([chord]).contains(chord) == true {
            send(.key(.keyDown(keyCode: chord, modifiers: pair.keys.flagModifiers), at: at))
        }
        send(.key(event, at: at))
    }

    /// The owner's turn stopped listening for a reason of its own (Esc, a failed start): the machine forgets it. It
    /// names the last turn the owner was given. When the machine has ended that turn itself (the echo of its own `send`
    /// or `cancel`) or has opened another since, the machine leaves everything as it is.
    func turnEnded() { send(.abandon(turn: ownerTurn)) }

    /// Sleep or wake: an open turn is cancelled, and nothing begins until every key is up.
    func interrupt() { send(.interrupt(live: liveModifiers())) }

    /// A key the monitor reads changed (a setting, VoiceOver): one tick so a turn the change ends is ended at once, as turning the
    /// second key off in the middle of a hands-free turn must.
    func configChanged() { tick() }

    /// A mouse button went down (left, right, other, a drag starts with one): an Option-click or Option-drag is not a talk turn.
    /// The second talk key's turn, armed or held, is over and never sent; the primary key is not told (`TalkKeyPair.mouseDown`).
    func mouseDown() {
        guard role == .talk else { return }
        let config = config, second = secondConfig
        let before = pair.generation
        run(pair.mouseDownTagged(at: now(), primary: config, second: second), before: before, config, second)
    }

    /// Sleep and wake tell the machine to drop an open turn. Idempotent.
    func observeSleep(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        guard sleepObservers.isEmpty else { return }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            sleepObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.interrupt() }
            })
        }
    }

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
                                      confirm: confirmProvider?() ?? key.map(Self.tilingConfirm) ?? 0,
                                      chord: role == .talk ? chordProvider() : nil)
    }

    /// The second talk key's config: a hold key with the typing confirm (or tiling's, when longer) and no chord. Only the talk
    /// role has one.
    private var secondConfig: VoiceKeyMachine.Config {
        let key = role == .talk ? secondKeyProvider() : nil
        return VoiceKeyMachine.Config(key: key, role: .talk, mode: .hold,
                                      voiceOverHoldsKey: key == .controlOption && voiceOverProvider(),
                                      confirm: key.map { VoiceKey.secondTalkConfirm(tiling: Self.tilingConfirm($0)) } ?? 0, chord: nil)
    }

    /// The effects of one event run in order after the machine has handled it, so an owner that calls `turnEnded()` from
    /// inside a callback meets the machine in its new state. The k-th `start` of a call is turn `generation before + k`.
    private func send(_ event: VoiceKeyMachine.Event) {
        let config = config, second = secondConfig
        let before = pair.generation
        run(pair.handleTagged(event, primary: config, second: second), before: before, config, second)
    }

    /// Runs what the pair let through, in order. `before` is the pair's generation ahead of the call: the k-th `start` of a call is
    /// turn `before + k`.
    private func run(_ effects: [(slot: TalkKeyPair.Slot, effect: VoiceKeyMachine.Effect)], before: Int,
                     _ config: VoiceKeyMachine.Config, _ second: VoiceKeyMachine.Config) {
        var started = 0
        for (slot, effect) in effects {
            let heard = slot == .second ? second : config
            switch effect {
            case .start:
                started += 1
                let turn = before + started
                ownerTurn = turn
                VoiceLog.log("key", "\(role == .talk ? "talk" : "dictation") shortcut down (\(heard.key?.title ?? "none"))")
                if onPress?() == false { send(.abandon(turn: turn)) }
            case .send:
                // A launcher or another app may hold Option-Space (Carbon cannot see it): a Space the system reports down at the release
                // of a second-key turn means the person was not talking, so the turn is cancelled, not sent.
                if slot == .second, keysStillDown?([49]).contains(49) == true {
                    VoiceLog.log("key", "talk shortcut (\(heard.key?.title ?? "none")) released with Space down: cancelled, nothing sent")
                    onCancel?()
                } else {
                    onRelease?()
                }
            case .cancel:
                VoiceLog.log("key", "\(role == .talk ? "talk" : "dictation") shortcut (\(heard.key?.title ?? "none")) became another shortcut: cancelled, nothing sent")
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
