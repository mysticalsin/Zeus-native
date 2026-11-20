import SwiftUI
import ZeusCore

struct SensorySettingsSection: View {
    var body: some View {
        Text(SensorySectionSlot.slot.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(SensorySectionSlot.slot.title)
    }
}
