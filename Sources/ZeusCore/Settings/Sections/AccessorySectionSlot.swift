import Foundation

public enum AccessorySectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.accessory",
        title: "Accessory",
        filled: true,
        keys: [
            AccessoryPreferenceKey.earbudsOverlay,
            AccessoryPreferenceKey.overlayStyle,
            AccessoryPreferenceKey.speakerNames,
        ],
        order: 6,
        placement: .topbarTab(6)
    )
}
