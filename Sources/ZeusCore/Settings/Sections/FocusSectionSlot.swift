import Foundation

public enum FocusSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.focus", title: "Focus", filled: false, keys: [], order: 3, placement: .topbarTab(3)
    )
}
