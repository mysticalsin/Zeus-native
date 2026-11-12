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

/// Push-to-talk: fires while the shortcut chosen in Settings is held. Modifier chords, single
/// modifiers (Right Command, Fn) and keys with modifiers (⌥Space) are tracked from the event
/// stream by `ShortcutState`. Global monitoring needs Accessibility or Input Monitoring; the
/// local monitor covers ZEUS's own windows.
@MainActor
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Called when the key is held but can't be used (Control+Option while VoiceOver is on).
    var onBlocked: ((String) -> Void)?
    /// Which shortcut this monitor listens for; nil turns it off. Push-to-talk by default (moved off
    /// Control+Option while VoiceOver uses it, `VoiceKey.effectiveTalkKey`); dictation supplies its own.
    var keyProvider: () -> Shortcut? = {
        let dictation = DictationSettings.shared
        return VoiceKey.effectiveTalkKey(chosen: Preferences.shared.pushToTalk,
                                         dictation: dictation.enabled ? dictation.key : nil,
                                         pointing: PointingSettings.enabled ? PointingSettings.shortcut : nil,
                                         voiceOverOn: NSWorkspace.shared.isVoiceOverEnabled)
    }
    /// Dedicated dictation keys can toggle on each key-down instead of using TalkKeyLatch's
    /// hold/double-tap timing. Shared keys always use the existing gesture arbitration.
    var directPressProvider: () -> Bool = { false }
    /// When talk and dictation share one key, each monitor reacts to its own gesture of it:
    /// dictation to a hold, talk (command mode) to a double-tap.
    enum Role { case talk, dictation }
    var role: Role = .talk
    var sharedProvider: () -> Bool = { DictationSettings.shared.enabled && Preferences.shared.pushToTalk == DictationSettings.shared.key }
    /// A held dictation interrupted by a shortcut (the press became ⌘C). Defaults to release.
    var onCancel: (() -> Void)?
    /// The talk key: a hold of a modifier-only key that another key joins (⌃⌥Space for Chat) became a
    /// different shortcut, so the turn is cancelled through `onCancel` and nothing is sent.
    var cancelsWhenSpoiled = false

    private var keyMonitors: [Any] = []
    private var gesture = SharedKeyGesture()
    private var sharedDown = false
    private var holdTimer: DispatchWorkItem?
    private var commandLatched = false

    private var isDown = false
    private var latch = TalkKeyLatch()
    private var pendingStop: DispatchWorkItem?
    private var directPressActive = false

    private var state = ShortcutState()

    func start() {
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

    /// One keyboard event from either monitor (also the entry point for tests and the self-test).
    func feed(_ event: ShortcutEvent) {
        state.apply(event)
        if case .keyDown(let code, _) = event {
            // Only to spot shortcuts made with the shared key (⌘C): never reads or keeps the key.
            if keyProvider()?.keyCode != code { otherKeyPressed(); spoilHold() }
        }
        evaluate()
    }

    private func otherKeyPressed() {
        guard sharedDown else { return }
        if gesture.otherKey() == .holdCancelled { (onCancel ?? onRelease)?() }
        holdTimer?.cancel()
    }

    /// A held modifier-only talk key met another key: that press was a shortcut, not a question.
    /// `ShortcutState` keeps the chord unheld until every modifier is up, so it cannot restart mid-chord.
    private func spoilHold() {
        guard cancelsWhenSpoiled, role == .talk, isDown, let key = keyProvider(), key.isModifierOnly, !sharedProvider() else { return }
        isDown = false
        pendingStop?.cancel()
        pendingStop = nil
        latch = TalkKeyLatch()
        VoiceLog.log("key", "talk shortcut became another shortcut (\(key.title) + a key): cancelled, nothing sent")
        (onCancel ?? onRelease)?()
    }

    /// Shared-key path: raw down/up of the key plus "another modifier joined in".
    private func handleShared(_ key: Shortcut) {
        let now = ProcessInfo.processInfo.systemUptime
        let down = state.isHeld(key, exact: false)
        let extra = state.modifiers.subtracting(key.modifiers).subtracting(.function)
        if down, !gesture.isHolding, !extra.isEmpty { otherKeyPressed() }
        if down, !sharedDown {
            sharedDown = true
            if commandLatched, role == .talk {
                // Any tap ends a hands-free command.
                commandLatched = false
                onRelease?()
            }
            gesture.keyDown(at: now)
            holdTimer?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.gesture.holdTimerFired(at: ProcessInfo.processInfo.systemUptime) == .holdBegan, self.role == .dictation { self.onPress?() }
                }
            }
            holdTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + gesture.holdDelay, execute: work)
        } else if !down, sharedDown {
            sharedDown = false
            holdTimer?.cancel()
            switch gesture.keyUp(at: now) {
            case .holdEnded?: if role == .dictation { onRelease?() }
            case .doubleTap?: if role == .talk { commandLatched = true; onPress?() }
            default: break
            }
        }
    }

    private func evaluate() {
        guard let key = keyProvider() else {
            if isDown { isDown = false; onRelease?() }
            return
        }
        let shared = sharedProvider()
        let directPress = role == .dictation && !shared && directPressProvider()
        if directPress != directPressActive {
            directPressActive = directPress
            pendingStop?.cancel()
            pendingStop = nil
            latch = TalkKeyLatch()
            isDown = false
        }
        if shared {
            handleShared(key)
            return
        }
        let pressed = state.isHeld(key, exact: true)
        if directPress {
            if pressed, !isDown {
                if key == .controlOption, NSWorkspace.shared.isVoiceOverEnabled {
                    onBlocked?("VoiceOver is using Control and Option. Record another shortcut in ZEUS Settings.")
                    return
                }
                isDown = true
                onPress?()
            } else if !pressed, isDown {
                isDown = false
            }
            return
        }
        if pressed, !isDown {
            if key == .controlOption, NSWorkspace.shared.isVoiceOverEnabled {
                onBlocked?("VoiceOver is using Control and Option. Record another shortcut in ZEUS Settings.")
                return
            }
            isDown = true
            VoiceLog.log("key", "\(role == .talk ? "talk" : "dictation") shortcut down (\(key.title))")
            fire(latch.keyDown(at: ProcessInfo.processInfo.systemUptime))
        } else if !pressed, isDown {
            isDown = false
            fire(latch.keyUp(at: ProcessInfo.processInfo.systemUptime))
        }
    }

    /// Hold to talk; double-tap to keep listening hands-free until the next tap.
    private func fire(_ action: TalkKeyLatch.Action?) {
        switch action {
        case .start?: onPress?()
        case .stop?: onRelease?()
        case .stopLater(let gap)?:
            pendingStop?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pendingStop = nil
                    self.fire(self.latch.pendingStopFired())
                }
            }
            pendingStop = work
            DispatchQueue.main.asyncAfter(deadline: .now() + gap, execute: work)
        case .cancelPendingStop?:
            pendingStop?.cancel()
            pendingStop = nil
        case nil: break
        }
    }
}
