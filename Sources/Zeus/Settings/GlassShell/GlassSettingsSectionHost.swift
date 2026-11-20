import SwiftUI
import ZeusCore

/// Routes each slot to the view file that owns it. A section change edits that view, not this list.
enum GlassSettingsSectionHost {
    @ViewBuilder
    static func page(for id: String) -> some View {
        switch id {
        case MediaSectionSlot.slot.id: MediaSettingsSection()
        case GeneralSectionSlot.slot.id: GeneralSettingsSection()
        case PortalSectionSlot.slot.id: PortalSettingsSection()
        case SensorySectionSlot.slot.id: SensorySettingsSection()
        case BatterySectionSlot.slot.id: BatterySettingsSection()
        case FocusSectionSlot.slot.id: FocusSettingsSection()
        case WeatherSectionSlot.slot.id: WeatherSettingsSection()
        case LockScreenSectionSlot.slot.id: LockScreenSettingsSection()
        case FaceIDSectionSlot.slot.id: FaceIDSettingsSection()
        case AccessorySectionSlot.slot.id: AccessorySettingsSection()
        case LicenseSectionSlot.slot.id: LicenseSettingsSection()
        case AutoUpdateSectionSlot.slot.id: AutoUpdateSettingsSection()
        default: EmptyView()
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
            GlassSettingsSectionHost.page(for: slot.id)
        }
        .accessibilityElement(children: .contain)
    }
}
