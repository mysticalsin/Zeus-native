import SwiftUI
import ZeusCore

struct FocusSettingsSection: View {
    var body: some View {
        Text(FocusSectionSlot.slot.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(FocusSectionSlot.slot.title)
    }
}
