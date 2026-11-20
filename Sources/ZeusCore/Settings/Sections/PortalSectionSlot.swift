import Foundation

public enum PortalSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.portal", title: "Portal", filled: false, keys: [], order: 7, placement: .topbarTab(7)
    )
}
