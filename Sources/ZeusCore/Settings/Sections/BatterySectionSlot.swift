import Foundation

public enum BatterySectionSlot: GlassSlotProviding {
    public static var keyContributions: [SettingsKeyContribution] { [] }

    public static let descriptor = GlassSectionSlot(
        id: "glass.battery", title: "Battery", filled: true, keys: [], order: 2, placement: .topbarTab(2)
    )
}
