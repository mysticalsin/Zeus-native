import SwiftUI
import ZeusCore

struct LockScreenSettingsSection: View {
    var body: some View {
        Text(LockScreenSectionSlot.slot.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(LockScreenSectionSlot.slot.title)
    }
}
