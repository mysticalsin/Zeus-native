import Foundation
import ZeusCore

/// The tap as the layer uses it. `TilingKeyTap` is the real one; a test stands in with one that records its calls.
@MainActor
protocol TilingKeyTapping: AnyObject {
    func update(keymap: TileKeymap, enabled: Bool, paused: Bool)
    /// True when the tap is running.
    func start() -> Bool
    func stop()
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

    /// A bound chord was pressed. Runs on the main actor, after the tap callback has returned.
    var onAction: (TileAction) -> Void = { _ in }
    /// The tap cannot be created, or the system keeps turning it off. The layer has stopped it and stays
    /// stopped until tiling is turned off and on again. The owner pauses tiling and shows the state.
    var onUnavailable: () -> Void = {}

    private let environment: Environment
    private var tap: (any TilingKeyTapping)?
    private var wanted = false
    private var failed = false
    private var keymap = TileKeymap()
    private var paused = false

    init(environment: Environment = .live) {
        self.environment = environment
    }

    /// Whether the tap is installed right now.
    var isInstalled: Bool { tap != nil }

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
        let created = environment.makeTap(
            { [weak self] action in self?.onAction(action) },
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
        tap?.stop()
        tap = nil
    }
}
