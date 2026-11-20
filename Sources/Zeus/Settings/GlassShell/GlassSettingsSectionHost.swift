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

struct GlassSettingsFilledSections: View {
    var body: some View {
        let filled = GlassSectionManifest.slots.filter(\.filled)
        if !filled.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(filled, id: \.id) { slot in
                    GlassSettingsSectionHost.page(for: slot.id)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}
