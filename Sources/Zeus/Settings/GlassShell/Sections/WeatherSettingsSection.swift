import SwiftUI
import ZeusCore

struct WeatherSettingsSection: View {
    var body: some View {
        Text(WeatherSectionSlot.slot.title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(WeatherSectionSlot.slot.title)
    }
}
