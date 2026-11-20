import Foundation

public enum MediaSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.media", title: "Media", filled: true, keys: MediaSettingID.added, order: 0, placement: .topbarTab(0)
    )
}
