import Foundation

public enum BatterySectionSlot: GlassSlotProviding {
    public static var keyContributions: [SettingsKeyContribution] {
        [
            SettingsKeyContribution(
                id: BatteryOverlayStyle.storageKey,
                defaultValue: BatteryOverlayStyle.default.rawValue,
                kind: .choice,
                policy: .exportable
            ),
            SettingsKeyContribution(
                id: BatteryEarbudSetting.key,
                defaultValue: "false",
                kind: .toggle,
                policy: .importCannotEnable
            ),
        ]
    }

    public static let descriptor = GlassSectionSlot(
        id: "glass.battery", title: "Battery", filled: true, keys: [], order: 2, placement: .topbarTab(2)
    )
}
