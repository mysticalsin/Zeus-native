import SwiftUI
import ZeusCore

/// Settings > Sounds. The lock and wake chimes, with a file the owner already has on this Mac.
struct LockWakeChimesCard: View {
    private var store: SettingsStore { SettingsStore.shared }

    var body: some View {
        let soundFeedback = ExtraPreferences.shared.soundsOn
        let active = ChimeCardGate.interactive(soundFeedback: soundFeedback)
        let chimeOn = store.bool(ChimeSettingsKey.enabled)
        GSCard("Lock and wake") {
            GSToggleRow(symbol: "lock.laptopcomputer", title: "Lock and wake chimes",
                        text: "A soft chime when the Mac locks or sleeps, and another when it wakes. Quiet while Sound feedback is off, during a meeting, or when Focus status is not available. Zeus does not ask for Focus.",
                        isOn: store.boolBinding(ChimeSettingsKey.enabled))
                .disabled(!active)
            GSDivider()
            GSRow(symbol: "speaker.wave.1", title: "Volume", text: "How loud these chimes are. The Mac's output volume still applies.") {
                OBTickSlider(value: Binding(
                    get: { min(max(store.double(ChimeSettingsKey.volume), 0), 100) },
                    set: { store.set(ChimeSettingsKey.volume, String(Int($0.rounded()))) }),
                    range: 0...100, step: 5)
                    .frame(width: 220)
                    .environment(\.ob, OB.Palette.settings)
                    .accessibilityLabel("Lock and wake chime volume")
            }
            .disabled(!active || !chimeOn)
            .opacity(active && chimeOn ? 1 : 0.5)
            GSDivider()
            fileRow(.close, symbol: "lock", title: "Lock or sleep",
                    detail: "Lid close, a power button that sleeps or locks the display, or a session lock.")
            GSDivider()
            fileRow(.open, symbol: "sun.max", title: "Wake or unlock",
                    detail: "Wake, unlock, or lid open.")
            GSInfo(text: "The built-in chimes are Zeus's own. Choose sound reads a file on this Mac and does not copy it into the app.")
        }
        .disabled(!active)
        .opacity(active ? 1 : 0.5)
    }

    private func fileRow(_ event: ChimeEvent, symbol: String, title: String, detail: String) -> some View {
        let soundFeedback = ExtraPreferences.shared.soundsOn
        let active = ChimeCardGate.interactive(soundFeedback: soundFeedback)
        let chimeOn = store.bool(ChimeSettingsKey.enabled)
        let path = store.string(ChimeSettingsKey.pathID(event))
        let name = path.isEmpty ? "Built-in chime" : URL(fileURLWithPath: path).lastPathComponent
        return VStack(alignment: .leading, spacing: 0) {
            GSRow(symbol: symbol, title: title, text: "\(detail) \(name).")
            HStack(spacing: 8) {
                Button("Play") { LockChimeController.shared.preview(event) }
                    .buttonStyle(GSButtonStyle())
                    .disabled(!ChimeCardGate.playEnabled(soundFeedback: soundFeedback, chimeEnabled: chimeOn))
                    .accessibilityLabel("Play the \(title.lowercased()) chime")
                Button("Choose sound...") { LockChimeController.shared.chooseFile(for: event) }
                    .buttonStyle(GSButtonStyle())
                    .disabled(!active)
                    .accessibilityLabel("Choose sound for \(title.lowercased())")
                Button("Use default") { LockChimeController.shared.useDefault(for: event) }
                    .buttonStyle(GSButtonStyle())
                    .disabled(!active || path.isEmpty)
                    .accessibilityLabel("Use default \(title.lowercased()) chime")
            }
            .padding(.leading, GS.rowIconColumn)
            .padding(.bottom, 14)
        }
    }
}
