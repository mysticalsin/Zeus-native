import Foundation

public enum LockScreenSectionSlot: GlassSlotProviding {
    public static var keyContributions: [SettingsKeyContribution] { [] }

    public static let descriptor = GlassSectionSlot(
        id: "glass.lockScreen", title: "Lock Screen", filled: false, keys: [], order: 4, placement: .topbarTab(4)
    )
}
