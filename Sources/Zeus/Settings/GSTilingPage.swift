import SwiftUI
import ZeusCore

/// Settings › Tiling: the switch, the keys, the gaps and the split. Every row is a catalog row
/// (`scripts/gen-settings-catalog.py`) read through `FeatureSettings`; nothing here moves a window.
@MainActor
struct TilingSettingsPage: View {
    private var store: SettingsStore { .shared }

    var body: some View {
        GSPageHeading(section: .tiling, subtitle: "Arrange your windows from the keyboard.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Arrange") {
            GSToggleRow(symbol: "rectangle.split.2x2", title: "Arrange my windows from the keyboard",
                        text: "Snaps the windows on each screen into a tidy grid. Keys move focus, swap windows and flip a split. Off until you turn it on.",
                        isOn: store.boolBinding("tiling.enabled"))
            GSDivider()
            GSRow(symbol: "command", title: "Tiling keys",
                  text: "Hold these with a letter or an arrow. Control-Option is also Talk to Zeus and pointing, so pick another pair if they clash.") {
                GSPopup(selection: store.stringBinding("tiling.keyBase"),
                        options: SettingsCatalog.option("tiling.keyBase")?.choices ?? [], label: "Tiling keys")
            }
            GSInfo(text: "Moving windows uses Accessibility. Zeus never asks for it from here: allow it in Permissions.")
        }
        GSCard("Layout") {
            sliderRow("tiling.innerGap", symbol: "arrow.left.and.right", title: "Gap between windows",
                      text: "Space between two tiled windows.", unit: "points")
            GSDivider()
            sliderRow("tiling.outerGap", symbol: "square.dashed", title: "Gap to the screen edge",
                      text: "Space between the windows and the edge of the screen.", unit: "points")
            GSDivider()
            sliderRow("tiling.splitRatio", symbol: "rectangle.split.2x1", title: "Default split",
                      text: "How much of a slot the window already there keeps when a new window joins it.", unit: "percent")
        }
        GSCard("Focus") {
            GSToggleRow(symbol: "viewfinder", title: "Ring the focused window",
                        text: "A thin ring around the window the tiling keys act on.", isOn: store.boolBinding("tiling.focusBorder"))
        }
        GSCard("Left out") {
            GSRow(symbol: "minus.circle", title: "Apps Zeus never tiles",
                  text: "Bundle ids, separated by commas. Their windows are left where they are.") {
                GSTextInput(text: store.stringBinding("tiling.excludedApps"), placeholder: "e.g. com.example.app", label: "Apps Zeus never tiles")
            }
        }
    }

    /// A slider over a catalog slider row's own range and step. A stored value that is not a number shows the row's default.
    private func sliderRow(_ id: String, symbol: String, title: String, text: String, unit: String) -> some View {
        let option = SettingsCatalog.option(id)
        let range = option?.range ?? SettingOption.Range(min: 0, max: 64, step: 4)
        let bounds = range.min...range.max
        let fallback = Double(option?.defaultValue ?? "") ?? range.min
        func current() -> Double {
            let stored = Double(store.string(id)).flatMap { $0.isFinite ? $0 : nil } ?? fallback
            return min(max(stored, range.min), range.max)
        }
        let shown = Int(current())
        return GSRow(symbol: symbol, title: title, text: "\(shown) \(unit). \(text)") {
            Slider(value: Binding(get: { current() }, set: { store.set(id, String(Int($0.rounded()))) }), in: bounds, step: range.step)
                .snapshotSafeSlider(value: current(), in: bounds)
                .frame(width: 160)
                .accessibilityLabel(title)
                .accessibilityValue("\(shown) \(unit)")
        }
    }
}
