import Foundation

/// Battery is a filled glass slot. The shell has no Topbar-tab placement yet;
/// `BatterySectionPlacement.topbarTab` is the order that placement will use.
public enum BatterySectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(
        id: "glass.battery",
        title: "Battery",
        filled: true,
        keys: [BatteryOverlayStyle.storageKey, BatteryEarbudSetting.key],
        order: 140
    )
}
