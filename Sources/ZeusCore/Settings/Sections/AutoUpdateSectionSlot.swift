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
}
