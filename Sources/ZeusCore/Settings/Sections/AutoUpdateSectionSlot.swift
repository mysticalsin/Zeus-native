import Foundation

public enum AutoUpdateSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(id: "glass.autoUpdate", title: "Auto-update", filled: false, keys: [], order: 210)
    /// Card title on the existing About page. The slot stays out of the sidebar.
    public static let cardTitle = "Updates"
    public static let aboutPageID = "about"
    /// First card hook on About: `.cardOn` order 1 once the shell placement API is present.
    public static let aboutCardOrder = 1
}
