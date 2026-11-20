import Foundation

public enum BatterySectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.battery", title: "Battery", filled: false, keys: [], order: 2, placement: .topbarTab(2)
    )
}
