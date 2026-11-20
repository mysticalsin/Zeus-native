import Foundation

public enum GeneralSectionSlot: GlassSlotProviding {
    public static let backgroundBlur = SettingsKeyContribution(
        id: "general.backgroundBlur", defaultValue: "40", kind: .number, policy: .exportable
    )
    public static let hideInFullScreen = SettingsKeyContribution(
        id: "general.hideInFullScreen", defaultValue: "false", kind: .toggle, policy: .exportable
    )
    public static let hapticFeedback = SettingsKeyContribution(
        id: "general.hapticFeedback", defaultValue: "false", kind: .toggle, policy: .exportable
    )

    public static var keyContributions: [SettingsKeyContribution] {
        [backgroundBlur, hideInFullScreen, hapticFeedback]
    }

    public static let descriptor = GlassSectionSlot(
        id: "glass.general",
        title: "General",
        filled: false,
        keys: [],
        order: 1,
        placement: .cardOn(.general, 1)
    )
}
