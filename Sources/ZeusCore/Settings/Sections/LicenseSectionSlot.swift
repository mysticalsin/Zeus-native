import Foundation

public enum LicenseSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.license", title: "License", filled: false, keys: [], order: 0, placement: .cardOn(.license, 0)
    )
}
