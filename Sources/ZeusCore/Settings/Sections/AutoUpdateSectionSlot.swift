import Foundation

public enum AutoUpdateSectionSlot: GlassSlotProviding {
    public static var keyContributions: [SettingsKeyContribution] { [] }

    public static let descriptor = GlassSectionSlot(
        id: "glass.autoUpdate", title: "Auto-update", filled: false, keys: [], order: 0, placement: .cardOn(.about, 0)
    )
}
