import SwiftUI
import ZeusCore

extension AutoUpdateSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(AutoUpdateSettingsSection()) }
}

struct AutoUpdateSettingsSection: View {
    var body: some View {
        Text(AutoUpdateSectionSlot.descriptor.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(AutoUpdateSectionSlot.descriptor.title)
    }
}
