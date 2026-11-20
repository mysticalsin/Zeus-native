import Foundation

public enum LicenseSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.license", title: "License", filled: true, keys: [], order: 1, placement: .cardOn(.license, 1)
    )
}
