import Foundation

public enum FocusSectionSlot: GlassSlotProviding {
    public static var keyContributions: [SettingsKeyContribution] {
        FocusSettingKey.optIn.map { id in
            SettingsKeyContribution(id: id, defaultValue: "false", kind: .toggle, policy: .importCannotEnable)
        }
    }

    public static let descriptor = GlassSectionSlot(
        id: "glass.focus", title: "Focus", filled: true, keys: [], order: 3, placement: .topbarTab(3)
    )
}
