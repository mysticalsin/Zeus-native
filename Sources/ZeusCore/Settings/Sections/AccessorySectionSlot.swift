import Foundation

public enum AccessorySectionSlot: GlassSlotProviding {
    public static let placement = AccessoryPlacement.topbarTab(6)
    public static let descriptor = GlassSectionSlot(
        id: "glass.accessory",
        title: "Accessory",
        filled: true,
        keys: [AccessoryPreferenceKey.earbudsOverlay, AccessoryPreferenceKey.overlayStyle, AccessoryPreferenceKey.speakerNames],
        order: 190
    )
}
