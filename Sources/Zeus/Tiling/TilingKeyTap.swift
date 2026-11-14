import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import ZeusCore

/// The keyboard tap for tiling: an active session event tap that consumes exactly the chords the keymap binds
/// while tiling is on, and passes every other event through untouched.
///
/// Isolation: the tap callback is a system callback. It is a file-private global function, and everything it
/// reaches is nonisolated code here, never inside a `@MainActor` type, so it carries no main-actor executor
/// assumption (the crash class in `SystemAuthorization` and `OffMainAudioCallbacks`). A matched action is handed
/// to the main actor after the callback returns, so no Accessibility work runs inside the tap.
///
/// Privacy: the callback copies a key code, the modifier flags and two booleans, asks the pure
/// `TileKeyMatcher`, and forgets them. It never reads a character, never logs, and never stores or forwards
/// what is typed. The only thing kept is the key codes of presses it consumed, to pair each with its key-up.
/// A consumed press and its release are handed to the other Zeus key monitors as a key code and modifiers only
/// (`TilingConsumedKey`), because an event the tap consumes never reaches them and a modifier-only hold they track
/// would otherwise not be spoiled by the chord. Only chords the owner bound are ever consumed, so this reports
/// nothing about typing.
///
/// Permission: this type never prompts. `start()` returns false when the tap cannot be created, and the owner
/// shows a notice. There is no fallback global monitor, because a monitor cannot consume an event.
final class TilingKeyTap: @unchecked Sendable {
    typealias Sink = @MainActor @Sendable (TileAction) -> Void
    typealias Failure = @MainActor @Sendable () -> Void

    private struct Snapshot {
        var keymap = TileKeymap()
        var gate = TileKeyGate(enabled: false)
    }

    private let lock = NSLock()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var snapshot = Snapshot()
    private var matcher = TileKeyMatcher()
    private var health = TileTapHealth()
    private let sink: Sink
    private let onFailure: Failure

    init(sink: @escaping Sink, onFailure: @escaping Failure) {
        self.sink = sink
        self.onFailure = onFailure
    }

    deinit { stop() }

    /// Replaces the keymap and the gate the callback reads. The callback only ever sees a whole snapshot.
    nonisolated func update(keymap: TileKeymap, enabled: Bool, paused: Bool) {
        lock.lock(); defer { lock.unlock() }
        snapshot = Snapshot(keymap: keymap, gate: TileKeyGate(enabled: enabled, paused: paused))
    }

    /// Idempotent. Returns true when the tap is running.
    nonisolated func start() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let port {
            CGEvent.tapEnable(tap: port, enable: true)
            return true
        }
        let types: [CGEventType] = [.keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: mask, callback: tilingTapCallback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else { return false }
        port = created; source = runLoopSource
        matcher.reset()
        health.reset()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    nonisolated func stop() {
        lock.lock(); defer { lock.unlock() }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        port = nil; source = nil
        matcher.reset()
    }

    var isRunning: Bool { lock.withLock { port != nil } }

    /// Called by the C callback. Returns nil to consume the event, or the event itself to pass it on.
    nonisolated fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            handleDisabled()
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            return handleKey(type: type, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private nonisolated func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        var modifiers: ShortcutModifiers = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
        let isDown = type == .keyDown
        let key = TileKeyEvent(
            phase: isDown ? .down : .up,
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: modifiers,
            isRepeat: isDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            isOwnInput: DriveInputAttribution.isOwnEvent(userData: event.getIntegerValueField(.eventSourceUserData)))
        // Only a chord that holds a consuming modifier can ever match, so the secure input check is skipped for
        // plain typing, which is nearly every event.
        let secure = isDown && !modifiers.isDisjoint(with: [.control, .option, .command]) && IsSecureEventInputEnabled()
        let decision: TileKeyDecision = lock.withLock {
            var gate = snapshot.gate
            gate.secureInput = secure
            return matcher.decide(key, keymap: snapshot.keymap, gate: gate)
        }
        switch decision {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .consume(let action):
            deliver(action, joined: decision.monitorEvent(for: key))
            return nil
        }
    }

    /// The system turned the tap off. Turn it back on, unless it keeps happening: then stay off and tell the owner.
    private nonisolated func handleDisabled() {
        let now = ProcessInfo.processInfo.systemUptime
        let (verdict, current): (TileTapHealth.Verdict, CFMachPort?) = lock.withLock {
            matcher.reset() // key-ups may have been missed while it was off
            return (health.recordDisable(at: now), port)
        }
        switch verdict {
        case .reenable:
            if let current { CGEvent.tapEnable(tap: current, enable: true) }
        case .giveUp:
            if let current { CGEvent.tapEnable(tap: current, enable: false) }
            let report = onFailure
            DispatchQueue.main.async { MainActor.assumeIsolated { report() } }
        }
    }

    /// Always hops to the main queue, even from the main thread, so the callback returns before any
    /// Accessibility work starts. The queue is first in, first out, so actions and consumed keys keep their order,
    /// and a monitor hears about a consumed key before any later modifier change.
    private nonisolated func deliver(_ action: TileAction?, joined: ShortcutEvent?) {
        guard action != nil || joined != nil else { return }
        let sink = self.sink
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let joined { TilingConsumedKey.post(joined) }
                if let action { sink(action) }
            }
        }
    }
}

/// A C callback cannot capture. It forwards to the owner through `userInfo`, which gives back the event to
/// pass it on, or nil to consume it.
private func tilingTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<TilingKeyTap>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
