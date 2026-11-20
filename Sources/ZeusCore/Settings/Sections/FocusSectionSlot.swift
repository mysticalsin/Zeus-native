import Foundation

public enum FocusSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.focus",
        title: "Focus",
        filled: true,
        keys: FocusSettingKey.optIn,
        order: 4,
        placement: .topbarTab(4)
    )
}
