import SwiftUI
import ZeusCore

struct GeneralSettingsSection: View {
    var body: some View {
        Text(GeneralSectionSlot.slot.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(GeneralSectionSlot.slot.title)
    }
}
