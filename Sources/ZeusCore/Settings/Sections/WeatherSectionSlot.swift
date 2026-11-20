import Foundation

public enum WeatherSectionSlot: GlassSlotProviding {
    public static var keyContributions: [SettingsKeyContribution] { [] }

    public static let descriptor = GlassSectionSlot(
        id: "glass.weather", title: "Weather", filled: true, keys: [], order: 1, placement: .topbarTab(1)
    )
}
