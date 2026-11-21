import SwiftUI
import ZeusCore

extension GeneralSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(GeneralSettingsSection()) }
}

struct GeneralSettingsSection: View {
    var body: some View {
        Text(GeneralSectionSlot.descriptor.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(GeneralSectionSlot.descriptor.title)
    }
}
