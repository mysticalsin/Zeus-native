import Foundation
import ZeusCore

/// The tap as the layer uses it. `TilingKeyTap` is the real one; a test stands in with one that records its calls.
@MainActor
protocol TilingKeyTapping: AnyObject {
    func update(keymap: TileKeymap, enabled: Bool, paused: Bool)
    /// True when the tap is running.
    func start() -> Bool
    /// True when the tap is gone: its thread has ended, or there was nothing to stop. False when the stop gave up
    /// waiting, so the tap and its port may still exist.
    @discardableResult
    func stop() -> Bool
}

extension TilingKeyTap: TilingKeyTapping {}

/// Owns the tiling key tap for the tiling controller. It decides when the tap exists and hands the tap the
/// current keymap; it holds no system callback of its own (the tap lives in nonisolated code, `TilingKeyTap`).
///
/// The tap exists only while tiling is on and Accessibility is granted. It is never installed otherwise, and it
/// is removed the moment tiling is turned off. Zeus never prompts here: while Accessibility is off the layer
/// waits through `AccessibilityGate.whenTrusted`, which polls without a prompt and starts the tap once the
/// owner grants it.
@MainActor
final class TilingKeyLayer {
    /// The shared key for the no-prompt Accessibility wait.
    static let gateKey = "tiling"

    /// Everything the layer touches outside itself, so a test can stand in for the permission and the system tap.
    @MainActor
    struct Environment {
        var isTrusted: () -> Bool
        /// Runs the work once Accessibility is on, without ever prompting; at once when it already is.
        var whenTrusted: (String, @escaping () -> Void) -> Void
        var cancelWaiting: (String) -> Void
        var makeTap: (@escaping TilingKeyTap.Sink, @escaping TilingKeyTap.Failure) -> any TilingKeyTapping

        static let live = Environment(
            isTrusted: { AccessibilityGate.trusted },
            whenTrusted: { key, work in AccessibilityGate.whenTrusted(key: key, work) },
            cancelWaiting: { AccessibilityGate.cancelWaiting(key: $0) },
            makeTap: { sink, onFailure in TilingKeyTap(sink: sink, onFailure: onFailure) })
    }

    /// A bound chord was pressed, and how many times it stands for (more than one only for a merged run of nudges).
    /// Runs on the main actor, after the tap callback has returned.
    var onAction: (TileAction, Int) -> Void = { _, _ in }
    /// The tap cannot be created, or the system keeps turning it off. The layer has stopped it and stays
    /// stopped until tiling is turned off and on again. The owner pauses tiling and shows the state.
    var onUnavailable: () -> Void = {}

    private let environment: Environment
    private var tap: (any TilingKeyTapping)?
    /// A removed tap whose stop gave up waiting. The layer keeps it, and builds no second tap, until a later stop sees
    /// its thread end; letting go of it would stop it once more in its deinit and make a second tap beside it.
    private var stopping: (any TilingKeyTapping)?
    private var wanted = false
    private var failed = false
    private var keymap = TileKeymap()
    private var paused = false

    init(environment: Environment = .live) {
        self.environment = environment
        AccessibilityGate.whenRevoked { [weak self] in self?.removeTap() }
        AccessibilityGate.whenRegained { [weak self] in self?.install() }
    }

    /// Whether the tap is installed right now.
    var isInstalled: Bool { tap != nil }

    /// How long `key`, a hold key, waits before it acts while this tap runs.
    func holdConfirm(for key: Shortcut) -> TimeInterval {
        tap == nil ? 0 : TileBaseConflicts.confirm(for: key, keymap: keymap)
    }

    /// Idempotent. Call it whenever tiling is switched, paused, or its keys change.
    func apply(enabled: Bool, paused: Bool, keymap: TileKeymap) {
        self.paused = paused
        self.keymap = keymap
        guard enabled else {
            wanted = false
            failed = false
            environment.cancelWaiting(Self.gateKey)
            removeTap()
            return
        }
        wanted = true
        guard !failed else { return }
        if let tap {
            if environment.isTrusted() {
                tap.update(keymap: keymap, enabled: true, paused: paused)
                return
            }
            // Accessibility was revoked: no tap stays installed without it.
            removeTap()
        }
        environment.whenTrusted(Self.gateKey) { [weak self] in self?.install() }
    }

    /// Removes the tap and stops waiting for Accessibility.
    func stop() {
        wanted = false
        environment.cancelWaiting(Self.gateKey)
        removeTap()
    }

    private func install() {
        guard wanted, !failed, tap == nil, environment.isTrusted() else { return }
        finishPendingStop()
        guard stopping == nil else {
            // The old tap's thread is still alive. Stay off until tiling is turned off and on again, and say so once.
            failed = true
            onUnavailable()
            return
        }
        let created = environment.makeTap(
            { [weak self] action, count in self?.onAction(action, count) },
            { [weak self] in self?.tapKeepsFailing() })
        created.update(keymap: keymap, enabled: true, paused: paused)
        guard created.start() else {
            failed = true
            onUnavailable()
            return
        }
        tap = created
    }

    private func tapKeepsFailing() {
        guard tap != nil else { return }
        failed = true
        removeTap()
        onUnavailable()
    }

    private func removeTap() {
        if let removed = tap {
            tap = nil
            stopping = removed
        }
        finishPendingStop()
    }

    /// Asks the removed tap to finish its stop. It is forgotten only once its thread has ended.
    private func finishPendingStop() {
        guard let pending = stopping else { return }
        if pending.stop() { stopping = nil }
    }
}
