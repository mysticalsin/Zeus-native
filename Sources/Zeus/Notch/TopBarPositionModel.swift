import AppKit
import Observation
import ZeusCore

/// Settings > Appearance > Top bar position. One global choice (see `TopBarPosition`), stored in
/// UserDefaults only after the owner moves the slider; until then every display uses its own automatic
/// default. Observed, so one write while dragging moves the notch, its light, ticker and wings in the
/// same pass, and the screen-edge glow and wave read the same value when they next draw.
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

    /// The offset a display with this notch height uses (0 for a display without a notch until chosen).
    func offset(forNotchHeight notchHeight: Double) -> Double {
        TopBarPosition.resolved(chosen: chosen, notchHeight: notchHeight)
    }

    /// The value the slider shows: the primary notched display's, or the main display's.
    var sliderValue: Double {
        let screens = NSScreen.screens
        let screen = screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? screens.first
        return offset(forNotchHeight: Double(screen?.safeAreaInsets.top ?? 0))
    }

    /// One call per drag event.
    func choose(_ value: Double) {
        let next = TopBarPosition.clamped(value)
        guard chosen != next else { return }
        chosen = next
        if !TopBarStyle.isSnapshot { defaults.set(next, forKey: Self.defaultsKey) }
    }

    /// Back to the automatic default.
    func reset() {
        guard chosen != nil else { return }
        chosen = nil
        if !TopBarStyle.isSnapshot { defaults.removeObject(forKey: Self.defaultsKey) }
    }
}
