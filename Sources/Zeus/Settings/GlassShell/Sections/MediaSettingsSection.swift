import SwiftUI
import ZeusCore

extension MediaSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(MediaSettingsSection()) }
}

/// The Media page. The host asks the slot for this view.
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
