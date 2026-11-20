import SwiftUI
import ZeusCore

extension LockScreenSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(LockScreenSettingsSection()) }
}

struct LockScreenSettingsSection: View {
    var body: some View {
        Text(LockScreenSectionSlot.descriptor.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(LockScreenSectionSlot.descriptor.title)
    }
}
