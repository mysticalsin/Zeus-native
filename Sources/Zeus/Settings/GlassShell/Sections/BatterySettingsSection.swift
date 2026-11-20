import SwiftUI
import ZeusCore

struct BatterySettingsSection: View {
    var body: some View {
        Text(BatterySectionSlot.slot.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(BatterySectionSlot.slot.title)
    }
}
