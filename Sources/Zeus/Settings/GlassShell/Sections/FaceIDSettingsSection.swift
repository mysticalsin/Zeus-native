import SwiftUI
import ZeusCore

struct FaceIDSettingsSection: View {
    var body: some View {
        Text(FaceIDSectionSlot.slot.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(FaceIDSectionSlot.slot.title)
    }
}
