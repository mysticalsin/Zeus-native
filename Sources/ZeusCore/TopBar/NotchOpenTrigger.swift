import CoreGraphics
import Foundation

/// What opens the closed notch: the pointer resting on it, or a click on it
/// (Settings > Appearance > Notch behavior > Open the notch on).
public enum NotchOpenTrigger: Sendable, Equatable {
    case hover
    case click

    /// The stored display string; anything unknown is `hover`, today's behaviour.
    public init(label: String) {
        self = label == "Click" ? .click : .hover
    }
}

/// Pure rules for opening the notch with a click. AppKit coordinates (origin bottom-left).
public enum NotchOpenRules {
    /// How far the click zone reaches past each side of the pill on a display without a notch.
    public static let pillSideGrowth: CGFloat = 12
    /// The click zone's height on a display without a notch, so it stays clear of menu bar items.
    public static let pillZoneHeight: CGFloat = 14

    /// Whether hovering the notch may open it.
    public static func opensOnHover(_ trigger: NotchOpenTrigger) -> Bool {
        trigger == .hover
    }

    /// Where a click opens the notch, in screen coordinates. On a notched display that is the hardware
    /// notch, which no other app can use, reaching down `topOffset` more so a lowered island is covered too
    /// (still only notch-wide, so menu bar items stay clear). A zero notch size means no notch: the pill's
    /// rectangle grown by 12 pt on each side and 14 pt tall, hanging from `topOffset` below the top edge.
    public static func clickZone(screenFrame: CGRect, notchSize: CGSize, topOffset: CGFloat) -> CGRect {
        if notchSize.width > 0, notchSize.height > 0 {
            let lowered = max(topOffset, 0)
            return CGRect(x: screenFrame.midX - notchSize.width / 2, y: screenFrame.maxY - notchSize.height - lowered,
                          width: notchSize.width, height: notchSize.height + lowered)
        }
        let width = NotchClosedBodyLayout.slimPillSize.width + 2 * pillSideGrowth
        let top = screenFrame.maxY - topOffset
        return CGRect(x: screenFrame.midX - width / 2, y: top - pillZoneHeight, width: width, height: pillZoneHeight)
    }

    /// Whether a click opens the notch: the trigger is Click, the panel is not already open and the point is
    /// in the zone. Only the panel counts as open: a peek is a notification, and a click promotes it, as
    /// hovering does. The top edge counts and the bottom edge does not, like the hover zone, so this is not
    /// CGRect.contains.
    public static func opensOnClick(trigger: NotchOpenTrigger, panelIsOpen: Bool, point: CGPoint, zone: CGRect) -> Bool {
        guard trigger == .click, !panelIsOpen else { return false }
        return point.x >= zone.minX && point.x <= zone.maxX && point.y > zone.minY && point.y <= zone.maxY
    }
}
