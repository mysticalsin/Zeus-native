import Foundation

public enum LockScreenSectionSlot: GlassSlotProviding {
    public static var keyContributions: [SettingsKeyContribution] { LockScreenSettingsStore.contributions }

    public static let descriptor = GlassSectionSlot(
        id: "glass.lockScreen", title: "Lock Screen", filled: true, keys: [], order: 4, placement: .topbarTab(4)
    )
}
