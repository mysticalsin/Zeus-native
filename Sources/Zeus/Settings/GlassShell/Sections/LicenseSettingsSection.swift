import SwiftUI
import ZeusCore

struct LicenseSettingsSection: View {
    var body: some View {
        Text(LicenseSectionSlot.slot.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(LicenseSectionSlot.slot.title)
    }
}
