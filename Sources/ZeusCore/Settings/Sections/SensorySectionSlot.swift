import Foundation

public enum SensorySectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.sensory",
        title: "Sensory",
        filled: true,
        keys: [SensorySettings.holdKey, SensorySettings.labelKey],
        order: 6,
        placement: .topbarTab(7)
    )
}
