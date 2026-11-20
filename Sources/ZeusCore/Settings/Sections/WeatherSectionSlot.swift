import Foundation

public enum WeatherSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.weather", title: "Weather", filled: true, keys: [], order: 2, placement: .topbarTab(2)
    )
}
