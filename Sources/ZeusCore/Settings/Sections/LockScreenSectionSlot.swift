import Foundation

public enum LockScreenSectionSlot: GlassSlotProviding {
    /// Stays unfilled until the shell can place this page on top bar tab 5.
    public static let descriptor = GlassSectionSlot(id: "glass.lockScreen", title: "Lock Screen", filled: false, keys: [], order: 170)
}
