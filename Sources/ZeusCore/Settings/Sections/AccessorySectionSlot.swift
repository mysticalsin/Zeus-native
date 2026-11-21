import Foundation

public enum AccessorySectionSlot: GlassSlotProviding {
    public static var keyContributions: [SettingsKeyContribution] {
        [
            SettingsKeyContribution(
                id: AccessoryPreferenceKey.earbudsOverlay,
                defaultValue: "false",
                kind: .toggle,
                policy: .importCannotEnable
            ),
            SettingsKeyContribution(
                id: AccessoryPreferenceKey.overlayStyle,
                defaultValue: "off",
                kind: .choice,
                policy: .importCannotEnable
            ),
            SettingsKeyContribution(
                id: AccessoryPreferenceKey.speakerNames,
                defaultValue: "false",
                kind: .toggle,
                policy: .importCannotEnable
            ),
        ]
    }

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
