import SwiftUI
import ZeusCore

extension SensorySectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(SensorySettingsSection()) }
}

struct SensorySettingsSection: View {
    var body: some View {
        Text(SensorySectionSlot.descriptor.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(SensorySectionSlot.descriptor.title)
    }
}
