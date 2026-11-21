import SwiftUI
import ZeusCore

extension MediaSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(MediaSettingsSection()) }
}

struct MediaSettingsSection: View {
    var body: some View {
        Text(MediaSectionSlot.descriptor.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(MediaSectionSlot.descriptor.title)
    }
}
