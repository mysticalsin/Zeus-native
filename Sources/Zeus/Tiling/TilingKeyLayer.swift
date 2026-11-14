import Foundation
import ZeusCore

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

    /// A bound chord was pressed. Runs on the main actor, after the tap callback has returned.
    var onAction: (TileAction) -> Void = { _ in }
    /// The tap cannot be created, or the system keeps turning it off. The layer has stopped it and stays
    /// stopped until tiling is turned off and on again. The owner pauses tiling and shows the state.
    var onUnavailable: () -> Void = {}

    private var tap: TilingKeyTap?
    private var wanted = false
    private var failed = false
    private var keymap = TileKeymap()
    private var paused = false

    /// Whether the tap is installed right now.
    var isInstalled: Bool { tap != nil }

    /// Idempotent. Call it whenever tiling is switched, paused, or its keys change.
    func apply(enabled: Bool, paused: Bool, keymap: TileKeymap) {
        self.paused = paused
        self.keymap = keymap
        guard enabled else {
            wanted = false
            failed = false
            AccessibilityGate.cancelWaiting(key: Self.gateKey)
            removeTap()
            return
        }
        wanted = true
        guard !failed else { return }
        if let tap {
            if AccessibilityGate.trusted {
                tap.update(keymap: keymap, enabled: true, paused: paused)
                return
            }
            // Accessibility was revoked: no tap stays installed without it.
            removeTap()
        }
        AccessibilityGate.whenTrusted(key: Self.gateKey) { [weak self] in self?.install() }
    }

    /// Removes the tap and stops waiting for Accessibility.
    func stop() {
        wanted = false
        AccessibilityGate.cancelWaiting(key: Self.gateKey)
        removeTap()
    }

    private func install() {
        guard wanted, !failed, tap == nil, AccessibilityGate.trusted else { return }
        let created = TilingKeyTap(
            sink: { [weak self] action in self?.onAction(action) },
            onFailure: { [weak self] in self?.tapKeepsFailing() })
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
