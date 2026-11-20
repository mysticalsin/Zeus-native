import SwiftUI
import ZeusCore

extension FocusSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(FocusSettingsSection()) }
}

struct FocusSettingsSection: View {
    var body: some View {
        Text(FocusSectionSlot.descriptor.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(FocusSectionSlot.descriptor.title)
    }
}
