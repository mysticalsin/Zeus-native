import SwiftUI
import ZeusCore

extension WeatherSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(WeatherSettingsSection()) }
}

struct WeatherSettingsSection: View {
    var body: some View {
        Text(WeatherSectionSlot.descriptor.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(WeatherSectionSlot.descriptor.title)
    }
}
