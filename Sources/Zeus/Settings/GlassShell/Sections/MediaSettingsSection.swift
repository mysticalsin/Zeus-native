import SwiftUI
import ZeusCore

/// The Media page. The shell mounts it when a section can supply its own view.
struct MediaSettingsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let store = SettingsStore.shared
        let settings = MediaSettings(reading: { id in
            let stored = store.string(id)
            return stored.isEmpty ? nil : stored
        })
        MediaSettingsPage(
            settings: settings,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            increaseContrast: contrast == .increased,
            write: { id, value in store.set(id, value) }
        )
    }
}
