import Foundation

/// Sensory is a top bar tab at order 7. The shell has no placement API yet, so the slot stays empty
/// and the page is not mounted in the sidebar.
public enum SensorySectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(id: "glass.sensory", title: "Sensory", filled: false, keys: [], order: 130)
}
