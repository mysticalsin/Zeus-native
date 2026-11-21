import SwiftUI
import ZeusCore

extension BatterySectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(BatterySettingsSection()) }
}

struct BatterySettingsSection: View {
    var body: some View {
        Text(BatterySectionSlot.descriptor.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(BatterySectionSlot.descriptor.title)
    }
}
