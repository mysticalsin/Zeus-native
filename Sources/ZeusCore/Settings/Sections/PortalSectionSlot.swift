import Foundation

public enum PortalSectionSlot: GlassSlotProviding {
    /// Portal adds no key. Nearby devices stay on the existing Shelf rows.
    public static var keyContributions: [SettingsKeyContribution] { [] }

    /// Eighth topbar tab. The placement API numbers tabs from zero, so this is `.topbarTab(7)`.
    public static let descriptor = GlassSectionSlot(
        id: "glass.portal", title: "Portal", filled: true, keys: [], order: 7, placement: .topbarTab(7)
    )
}
