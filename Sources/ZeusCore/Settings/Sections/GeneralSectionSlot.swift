import Foundation

public enum GeneralSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.general", title: "General", filled: false, keys: [], order: 0, placement: .cardOn(.general, 0)
    )
}
