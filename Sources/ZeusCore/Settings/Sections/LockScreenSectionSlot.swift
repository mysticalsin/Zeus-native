import Foundation

public enum LockScreenSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.lockScreen", title: "Lock Screen", filled: false, keys: [], order: 5, placement: .topbarTab(5)
    )
}
