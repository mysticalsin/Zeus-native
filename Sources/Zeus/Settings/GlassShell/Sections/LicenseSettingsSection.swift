import SwiftUI
import ZeusCore

extension LicenseSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(LicenseSettingsSection()) }
}

struct LicenseSettingsSection: View {
    var body: some View {
        Text(LicenseSectionSlot.descriptor.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(LicenseSectionSlot.descriptor.title)
    }
}
