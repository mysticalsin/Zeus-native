import SwiftUI
import ZeusCore

extension FaceIDSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(FaceIDSettingsSection()) }
}

struct FaceIDSettingsSection: View {
    var body: some View {
        Text(FaceIDSectionSlot.descriptor.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(FaceIDSectionSlot.descriptor.title)
    }
}
