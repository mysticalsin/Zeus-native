import SwiftUI
import ZeusCore

extension PortalSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(PortalSettingsSection()) }
}

struct PortalSettingsSection: View {
    var body: some View {
        Text(PortalSectionSlot.descriptor.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(PortalSectionSlot.descriptor.title)
    }
}
