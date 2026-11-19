import AppKit
import Observation
import ZeusCore

/// Settings > Appearance > Top bar position. One global choice (see `TopBarPosition`), stored in
/// UserDefaults only after the owner moves the slider; until then the closed bar sits flush with the top.
/// Observed, so one write while dragging moves the notch, its light, ticker and wings in the same pass.
/// The screen-edge glow and wave never read it: they hug the physical screen edge.
@MainActor
@Observable
final class TopBarPositionModel {
    static let shared = TopBarPositionModel()
    static let defaultsKey = "appearance.topBarOffset"

    /// nil until the owner moves the slider.
    private(set) var chosen: Double?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        chosen = TopBarStyle.isSnapshot ? nil : defaults.object(forKey: Self.defaultsKey) as? Double
    }

    /// The closed bar's drop on every display (0 until chosen). Also the value the slider shows.
    var offset: Double { TopBarPosition.resolved(chosen: chosen) }

    /// One call per drag event.
    func choose(_ value: Double) {
        let next = TopBarPosition.clamped(value)
        guard chosen != next else { return }
        chosen = next
        if !TopBarStyle.isSnapshot { defaults.set(next, forKey: Self.defaultsKey) }
    }

    /// Back to flush with the top.
    func reset() {
        guard chosen != nil else { return }
        chosen = nil
        if !TopBarStyle.isSnapshot { defaults.removeObject(forKey: Self.defaultsKey) }
    }
}
