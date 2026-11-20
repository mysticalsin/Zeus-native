import SwiftUI
import ZeusCore

/// Shows whatever slot the registry discovered. A new section file does not add a branch here.
enum GlassSettingsSectionHost {
    @ViewBuilder
    static func page(for slot: GlassSectionSlot) -> some View {
        let descriptor = SettingsSectionDescriptor(
            id: slot.id,
            title: slot.title,
            order: slot.order,
            accessibilityLabel: slot.title,
            placeholder: slot.keys.isEmpty ? slot.title : nil
        )
        if SettingsSectionHostPlan.hostedIDs(in: [descriptor]).contains(slot.id) {
            Text(descriptor.accessibilityLabel)
                .accessibilityLabel(descriptor.accessibilityLabel)
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
