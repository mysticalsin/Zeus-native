import Foundation

public enum BatterySectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.battery",
        title: "Battery",
        filled: true,
        keys: [BatteryOverlayStyle.storageKey, BatteryEarbudSetting.key],
        order: 3,
        placement: .topbarTab(3)
    )
}
