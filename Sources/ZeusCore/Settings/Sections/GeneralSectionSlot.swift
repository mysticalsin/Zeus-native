import Foundation

public enum GeneralSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.general",
        title: "General",
        filled: true,
        keys: ["general.backgroundBlur", "general.hideInFullScreen", "general.hapticFeedback"],
        order: 1,
        placement: .cardOn(.general, 1)
    )
}
