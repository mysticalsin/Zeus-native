import SwiftUI
import ZeusCore

/// The app-side page for a compile-time slot provider. The host asks the provider; it does not branch on the id.
protocol GlassSlotPage: GlassSlotProviding {
    static func erasePage() -> AnyView
}

enum GlassSettingsSectionHost {
    @ViewBuilder
    static func page(for slot: GlassSectionSlot) -> some View {
        if let provider = GlassSectionManifest.providers.first(where: { $0.descriptor.id == slot.id }),
           let page = provider as? any GlassSlotPage.Type {
            page.erasePage()
        } else {
            Text(slot.title)
                .accessibilityLabel(slot.title)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

struct GlassSettingsSlotPage: View {
    let slot: GlassSectionSlot

    var body: some View {
        let exposed = GlassSettingsAccessibility.exposure(slots: [slot])
        VStack(alignment: .leading, spacing: 8) {
            if let item = exposed.first {
                Text(item.label)
                    .accessibilityLabel(item.label)
                    .accessibilityAddTraits(item.heading ? .isHeader : [])
                    .accessibilityHidden(item.hidden)
            }
            GlassSettingsSectionHost.page(for: slot)
        }
        .accessibilityElement(children: .contain)
    }
}
