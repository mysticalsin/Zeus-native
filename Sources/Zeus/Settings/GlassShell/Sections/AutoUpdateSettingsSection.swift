import SwiftUI
import ZeusCore

struct AutoUpdateSettingsSection: View {
    var body: some View {
        Text(AutoUpdateSectionSlot.slot.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(AutoUpdateSectionSlot.slot.title)
    }
}
