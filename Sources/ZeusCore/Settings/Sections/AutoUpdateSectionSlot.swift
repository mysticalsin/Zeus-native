import Foundation

public enum AutoUpdateSectionSlot: GlassSlotProviding {
    /// Shown on the existing About page. Order 1 is the Updates card. The sidebar title stays Auto-update.
    public static let descriptor = GlassSectionSlot(
        id: "glass.autoUpdate",
        title: "Auto-update",
        filled: true,
        keys: [],
        order: 0,
        placement: .cardOn(.about, 1)
    )
    public static let cardTitle = "Updates"

    /// `about.autoUpdate` stays a catalog row. The shell rejects a second contribution of a catalog id.
    /// The feed address and SUPublicEDKey are build configuration, not settings keys.
    public static var keyContributions: [SettingsKeyContribution] {
        [
            SettingsKeyContribution(id: "about.autoInstall", defaultValue: "false", kind: .toggle, policy: .importCannotEnable),
            SettingsKeyContribution(id: "about.lastChecked", defaultValue: "", kind: .text, policy: .localOnly),
            SettingsKeyContribution(id: "about.updateStatus", defaultValue: "", kind: .text, policy: .localOnly),
            SettingsKeyContribution(id: "about.updateNotes", defaultValue: "", kind: .text, policy: .localOnly),
        ]
    }
}
