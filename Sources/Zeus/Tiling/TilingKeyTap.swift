import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import ZeusCore

/// The keyboard tap for tiling: an active session event tap that consumes exactly the chords the keymap binds
/// while tiling is on, and passes every other event through untouched.
///
/// Threading: the tap is serviced by a thread of its own with its own run loop (`TilingRunLoopThread`), never the main
/// one. A consuming tap makes the window server hold every keystroke in every app until the callback has answered,
/// and every Accessibility pass runs on the main thread, where one slow app can take a second. On a loop of its own the
/// callback answers within microseconds whatever main is doing, so the system never disables the tap for being slow.
/// `start()` and `stop()` are safe from any thread (the owner calls them on the main actor). `stop()` removes the source
/// and invalidates the port on the tap thread's own loop, after any callback in flight, and waits for the thread to end,
/// so a callback never meets a freed port and switching tiling off and on leaves nothing behind. The life of the tap
/// (off, starting, live, stopping, failed) is the pure `TileTapLife`; the lock here only makes its decisions atomic.
///
/// Isolation: the tap callback is a system callback. It is a file-private global function, and everything it
/// reaches is nonisolated code here, never inside a `@MainActor` type, so it carries no main-actor executor
/// assumption (the crash class in `SystemAuthorization` and `OffMainAudioCallbacks`). The callback decides consume or
/// pass from a lock-protected snapshot only, makes no Accessibility call and waits on nothing. A matched action goes
/// through a `TileActionMailbox` to the main actor after the callback has returned its answer, and a held focus key
/// cannot queue one window scan per repeat: the newest request wins.
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

    /// One run of the tap: its port and source, and the thread that services them. The callback reaches it through
    /// `userInfo` (not retained: the thread's closures hold it until the port is invalidated, which is after the last
    /// callback). The owner is weak, so a callback never keeps a tap alive.
    fileprivate final class Run: @unchecked Sendable {
        weak var owner: TilingKeyTap?
        var port: CFMachPort?
        var source: CFRunLoopSource?
        var thread: TilingRunLoopThread?
        init(owner: TilingKeyTap) { self.owner = owner }
    }

    private let lock = NSLock()
    private var life = TileTapLife()
    private var run: Run?
    private var snapshot = Snapshot()
    private var matcher = TileKeyMatcher()
    private var health = TileTapHealth()
    private var mailbox = TileActionMailbox()
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

    /// Idempotent. Returns true when the tap is running (or being installed by its thread).
    nonisolated func start() -> Bool {
        lock.lock(); defer { lock.unlock() }
        switch life.handle(.startRequested) {
        case .createTap:
            return create()
        case .enableTap:
            if let port = run?.port { CGEvent.tapEnable(tap: port, enable: true) }
            return true
        case .none, .disableTap, .tearDown:
            return life.isRunning
        }
    }

    /// Creates the tap and starts its thread. The caller holds the lock and has moved the life to `starting`.
    private nonisolated func create() -> Bool {
        let run = Run(owner: self)
        let types: [CGEventType] = [.keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: tilingTapCallback,
                                           userInfo: Unmanaged.passUnretained(run).toOpaque()) else {
            _ = life.handle(.createFailed)
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            _ = life.handle(.createFailed)
            return false
        }
        run.port = port
        run.source = source
        matcher.reset()
        health.reset()
        mailbox.reset()
        self.run = run
        run.thread = TilingRunLoopThread(
            name: "app.zeus.tiling.keytap",
            install: { [run] in
                guard let port = run.port, let source = run.source else { return }
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CGEvent.tapEnable(tap: port, enable: true)
                run.owner?.installed(run)
            },
            teardown: { [run] in
                guard let port = run.port, let source = run.source else { return }
                CGEvent.tapEnable(tap: port, enable: false)
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
                CFMachPortInvalidate(port)
            })
        return true
    }

    private nonisolated func installed(_ installed: Run) {
        lock.lock(); defer { lock.unlock() }
        guard run === installed else { return }
        _ = life.handle(.installed)
    }

    /// Removes the tap and ends its thread, and returns once both are gone. Safe to call again and from any thread.
    nonisolated func stop() {
        lock.lock()
        let effect = life.handle(.stopRequested)
        matcher.reset()
        mailbox.reset()
        let stopping = run
        lock.unlock()
        // The wait is outside the lock: the callback takes it, and the teardown waits for the callback.
        guard effect == .tearDown, let stopping, let thread = stopping.thread else { return }
        thread.stop()
        lock.lock(); defer { lock.unlock() }
        if run === stopping { run = nil }
        _ = life.handle(.threadEnded)
    }

    var isRunning: Bool { lock.withLock { life.isRunning } }

    /// Called by the C callback, on the tap thread. Returns nil to consume the event, or the event itself to pass it on.
    nonisolated fileprivate func handle(type: CGEventType, event: CGEvent, run: Run) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            handleDisabled(run)
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

    /// The system turned the tap off. The health rule says how often; the life says what to do with that. Turn it back
    /// on, unless it keeps happening: then stay off and tell the owner.
    private nonisolated func handleDisabled(_ run: Run) {
        let now = ProcessInfo.processInfo.systemUptime
        let effect: TileTapLife.Effect = lock.withLock {
            matcher.reset() // key-ups may have been missed while it was off
            return life.handle(.systemDisabled(health.recordDisable(at: now)))
        }
        guard let port = run.port else { return }
        switch effect {
        case .enableTap:
            CGEvent.tapEnable(tap: port, enable: true)
        case .disableTap:
            CGEvent.tapEnable(tap: port, enable: false)
            let report = onFailure
            DispatchQueue.main.async { MainActor.assumeIsolated { report() } }
        case .none, .createTap, .tearDown:
            break
        }
    }

    /// Hands a consumed key to the other monitors and puts the action in the mailbox, scheduling the one drain that runs
    /// the waiting actions when none is scheduled yet. Everything hops to the main queue, even from the main thread, so
    /// the callback returns before any work starts. The queue is first in, first out, so a monitor hears about a consumed
    /// key before any later modifier change. Internal so a test can send actions without a system event.
    nonisolated func deliver(_ action: TileAction?, joined: ShortcutEvent?) {
        if let joined {
            DispatchQueue.main.async { MainActor.assumeIsolated { TilingConsumedKey.post(joined) } }
        }
        if let action, lock.withLock({ mailbox.push(action) }) {
            DispatchQueue.main.async { [self] in drain() }
        }
    }

    /// On the main queue: runs one waiting action. The mailbox is popped before the action runs, so requests that
    /// arrive during a long scan merge behind it, and the next drain runs only the newest.
    private nonisolated func drain() {
        guard let next = lock.withLock({ mailbox.pop() }) else { return }
        MainActor.assumeIsolated { sink(next.action) }
        if next.more { DispatchQueue.main.async { [self] in drain() } }
    }
}

/// A C callback cannot capture. It forwards to the run through `userInfo`, which gives back the event to pass it on,
/// or nil to consume it.
private func tilingTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let run = Unmanaged<TilingKeyTap.Run>.fromOpaque(refcon).takeUnretainedValue()
    guard let owner = run.owner else { return Unmanaged.passUnretained(event) }
    return owner.handle(type: type, event: event, run: run)
}
