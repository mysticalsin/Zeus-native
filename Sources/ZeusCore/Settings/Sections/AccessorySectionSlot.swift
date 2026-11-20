import Foundation

public enum AccessorySectionSlot: GlassSlotProviding {
    public static var keyContributions: [SettingsKeyContribution] { [] }

    public static let descriptor = GlassSectionSlot(
        id: "glass.accessory", title: "Accessory", filled: false, keys: [], order: 5, placement: .topbarTab(5)
    )
}
