import Foundation

public enum PortalSectionSlot: GlassSlotProviding {
    /// Eighth topbar tab. The landed placement API numbers tabs from zero, so this is `.topbarTab(7)`.
    public static let descriptor = GlassSectionSlot(
        id: "glass.portal", title: "Portal", filled: true, keys: [], order: 7, placement: .topbarTab(7)
    )
}
