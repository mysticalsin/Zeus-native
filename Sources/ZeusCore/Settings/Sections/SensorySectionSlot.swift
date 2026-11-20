import Foundation

public enum SensorySectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.sensory", title: "Sensory", filled: false, keys: [], order: 6, placement: .topbarTab(6)
    )
}
