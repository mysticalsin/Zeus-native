import Foundation

public enum FaceIDSectionSlot: GlassSlotProviding {
    /// The approval switch is registered in the settings catalog, not as a second key.
    public static var keyContributions: [SettingsKeyContribution] { [] }

    /// The card is on the existing Privacy page. It is not a sidebar row.
    public static let descriptor = GlassSectionSlot(
        id: "glass.faceID",
        title: "Face ID",
        filled: true,
        keys: [],
        order: 1,
        placement: .cardOn(.privacy, 1)
    )
}
