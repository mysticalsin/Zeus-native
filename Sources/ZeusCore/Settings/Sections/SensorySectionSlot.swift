import Foundation

public enum SensorySectionSlot: GlassSlotProviding {
    public static var keyContributions: [SettingsKeyContribution] {
        [
            SettingsKeyContribution(id: SensorySettings.holdKey, defaultValue: "1.2", kind: .number, policy: .exportable),
            SettingsKeyContribution(id: SensorySettings.labelKey, defaultValue: "icon", kind: .choice, policy: .exportable),
        ]
    }

    public static let descriptor = GlassSectionSlot(
        id: "glass.sensory", title: "Sensory", filled: true, keys: [], order: 6, placement: .topbarTab(6)
    )
}
