import Foundation

public enum MediaSectionSlot: GlassSlotProviding {
    /// New player preferences. None of them start capture or read now-playing on their own.
    public static var keyContributions: [SettingsKeyContribution] {
        [
            SettingsKeyContribution(id: MediaSettingID.playerLook, defaultValue: "art", kind: .choice, policy: .exportable),
            SettingsKeyContribution(id: MediaSettingID.tint, defaultValue: "false", kind: .toggle, policy: .exportable),
            SettingsKeyContribution(id: MediaSettingID.like, defaultValue: "false", kind: .toggle, policy: .exportable),
            SettingsKeyContribution(id: MediaSettingID.explicitBadge, defaultValue: "false", kind: .toggle, policy: .exportable),
            SettingsKeyContribution(id: MediaSettingID.explicitColour, defaultValue: "false", kind: .toggle, policy: .exportable),
            SettingsKeyContribution(id: MediaSettingID.leftButton, defaultValue: "previous", kind: .choice, policy: .exportable),
            SettingsKeyContribution(id: MediaSettingID.hideOnPause, defaultValue: "never", kind: .choice, policy: .exportable),
        ]
    }

    public static let descriptor = GlassSectionSlot(
        id: "glass.media", title: "Media", filled: true, keys: MediaSettingID.added, order: 0, placement: .topbarTab(0)
    )
}
