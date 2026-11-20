import SwiftUI
import ZeusCore

struct AccessorySettingsSection: View {
    var body: some View {
        Text(AccessorySectionSlot.slot.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(AccessorySectionSlot.slot.title)
    }
}
