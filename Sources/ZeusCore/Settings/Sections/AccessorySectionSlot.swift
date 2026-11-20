import Foundation

public enum AccessorySectionSlot: GlassSlotProviding {
    public static var keyContributions: [SettingsKeyContribution] { [] }

    public static let descriptor = GlassSectionSlot(
        id: "glass.accessory",
        title: "Accessory",
        filled: true,
        keys: [
            AccessoryPreferenceKey.earbudsOverlay,
            AccessoryPreferenceKey.overlayStyle,
            AccessoryPreferenceKey.speakerNames,
        ],
        order: 5,
        placement: .topbarTab(5)
    )
}
