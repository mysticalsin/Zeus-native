import SwiftUI
import ZeusCore

struct MediaSettingsSection: View {
    var body: some View {
        Text(MediaSectionSlot.slot.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(MediaSectionSlot.slot.title)
    }
}
