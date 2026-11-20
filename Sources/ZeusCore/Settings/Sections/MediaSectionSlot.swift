import Foundation

public enum MediaSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.media", title: "Media", filled: false, keys: [], order: 0, placement: .topbarTab(0)
    )
}
