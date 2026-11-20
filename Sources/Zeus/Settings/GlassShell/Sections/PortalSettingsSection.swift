import SwiftUI
import ZeusCore

struct PortalSettingsSection: View {
    var body: some View {
        Text(PortalSectionSlot.slot.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(PortalSectionSlot.slot.title)
    }
}
