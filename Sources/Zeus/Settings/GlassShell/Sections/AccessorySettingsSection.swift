import SwiftUI
import ZeusCore

extension AccessorySectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(AccessorySettingsSection()) }
}

struct AccessorySettingsSection: View {
    var body: some View {
        Text(AccessorySectionSlot.descriptor.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(AccessorySectionSlot.descriptor.title)
    }
}
