import CoreGraphics
import Foundation

/// What a display reports about its top edge, as plain numbers (0 for a side area that is missing).
public struct NotchDisplayFacts: Sendable, Equatable {
    public var frame: CGRect
    public var safeAreaTop: CGFloat
    public var leftAreaWidth: CGFloat
    public var rightAreaWidth: CGFloat

    public init(frame: CGRect, safeAreaTop: CGFloat, leftAreaWidth: CGFloat, rightAreaWidth: CGFloat) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.leftAreaWidth = leftAreaWidth
        self.rightAreaWidth = rightAreaWidth
    }
}

/// The shape the closed notch takes on one display: the hardware notch, or where there is none the slim pill or
/// the shape the owner drew.
public enum NotchFootprint: Sendable, Equatable {
    case hardware(CGSize)
    case pill
    /// A drawn notch, already fitted to its display. It is laid out as a hardware notch of that size.
    case drawn(DrawnNotchShape)

    /// The hardware size, and zero for the pill: what the layout calls the notch.
    public var layoutSize: CGSize {
        switch self {
        case .hardware(let size): size
        case .pill: .zero
        case .drawn(let shape): CGSize(width: shape.width, height: shape.height)
        }
    }

    /// The closed, idle shape.
    public var idleSize: CGSize {
        switch self {
        case .hardware(let size): size
        case .pill: NotchClosedBodyLayout.slimPillSize
        case .drawn(let shape): CGSize(width: shape.width, height: shape.height)
        }
    }

    /// The width the wings grow from.
    public var wingBase: CGFloat {
        switch self {
        case .hardware(let size): size.width
        case .pill: 40
        case .drawn(let shape): CGFloat(shape.width)
        }
    }

    public var isPill: Bool {
        if case .pill = self { return true }
        return false
    }
}

/// Where the closed notch is centred. Every zone rule centres on the frame it is given, so a controller passes
/// the anchor frame to them and keeps the real frame for picking a display and placing the window.
public enum NotchAnchor {
    /// How far the notch sits right of the display's centre: the fitted offset of a drawn shape, else 0. An
    /// offset that is not a number moves nothing.
    public static func offset(_ footprint: NotchFootprint) -> CGFloat {
        guard case .drawn(let shape) = footprint, shape.offset.isFinite else { return 0 }
        return CGFloat(shape.offset)
    }

    /// The screen frame moved sideways by the offset. The hardware notch and the pill stay centred.
    public static func frame(screenFrame: CGRect, footprint: NotchFootprint) -> CGRect {
        screenFrame.offsetBy(dx: offset(footprint), dy: 0)
    }
}

/// The three inputs of the closed-body layout, kept apart, with the extra width a cue adds.
public struct ClosedWingsFacts: Hashable, Sendable {
    public var kindIsNone: Bool
    public var hasLights: Bool
    public var hasLiveActivity: Bool
    public var extraWidth: CGFloat

    public init(kindIsNone: Bool, hasLights: Bool, hasLiveActivity: Bool, extraWidth: CGFloat) {
        self.kindIsNone = kindIsNone
        self.hasLights = hasLights
        self.hasLiveActivity = hasLiveActivity
        self.extraWidth = extraWidth
    }

    /// A top bar with nothing to show: no wing kind, no light, no live activity.
    public static let noWings = ClosedWingsFacts(kindIsNone: true, hasLights: false, hasLiveActivity: false, extraWidth: 0)

    /// Whether the closed body grows its wings.
    public var showsWings: Bool {
        NotchClosedBodyLayout.showWings(closedWingKindIsNone: kindIsNone, hasLights: hasLights, hasLiveActivity: hasLiveActivity)
    }

    /// Everything the closed width depends on except the footprint. The closed width spring is keyed on it.
    public struct MotionKey: Hashable, Sendable {
        let kindIsNone: Bool
        let showsWings: Bool
        let extraWidth: CGFloat
    }

    public var motionKey: MotionKey {
        MotionKey(kindIsNone: kindIsNone, showsWings: showsWings, extraWidth: showsWings ? extraWidth : 0)
    }
}

public enum NotchFootprintRules {
    /// The hardware notch: a top inset and a menu bar area either side of it, all finite, with room between the
    /// areas. Nil for anything else.
    public static func hardwareSize(_ facts: NotchDisplayFacts) -> CGSize? {
        // `CGRect.width` reports a negative size as positive, so the stored size is read.
        let frame = facts.frame
        let numbers = [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
                       facts.safeAreaTop, facts.leftAreaWidth, facts.rightAreaWidth]
        guard numbers.allSatisfy(\.isFinite), frame.size.width > 0, frame.size.height > 0,
              facts.safeAreaTop > 0, facts.leftAreaWidth > 0, facts.rightAreaWidth > 0 else { return nil }
        let width = frame.size.width - facts.leftAreaWidth - facts.rightAreaWidth
        guard width > 0 else { return nil }
        return CGSize(width: width, height: facts.safeAreaTop)
    }

    public static func resolve(_ facts: NotchDisplayFacts) -> NotchFootprint {
        hardwareSize(facts).map(NotchFootprint.hardware) ?? .pill
    }

    /// The hardware notch wins. Without one, the pill for the pill style or when the display cannot hold the
    /// shape, else the shape fitted to the display's width.
    public static func resolve(_ facts: NotchDisplayFacts, style: NotchlessStyle, shape: DrawnNotchShape) -> NotchFootprint {
        if let size = hardwareSize(facts) { return .hardware(size) }
        guard style == .drawn,
              let fitted = DrawnNotchLimits.fitted(shape, screenWidth: Double(facts.frame.size.width)) else { return .pill }
        return .drawn(fitted)
    }

    /// The closed body as `NotchView` draws it: the idle size, or the wings grown from the wing base. A drawn
    /// notch has no shoulders while idle, like the hardware notch. Nil wings is a bare idle notch.
    public static func closedSize(_ footprint: NotchFootprint, wings: ClosedWingsFacts?) -> CGSize {
        let facts = wings ?? .noWings
        let hasNotch = !footprint.isPill
        let shoulder: CGFloat = hasNotch && !facts.kindIsNone ? 8 : 0
        let size = footprint.layoutSize
        let height = closedHeight(footprint, wings: wings)
        if facts.showsWings {
            let width = NotchClosedBodyLayout.bodyWidth(
                notchWidth: footprint.wingBase, shoulder: shoulder, showWings: true, extraWidth: facts.extraWidth,
                hasNotch: hasNotch, slimPill: footprint.isPill)
            return CGSize(width: width, height: height)
        }
        guard hasNotch else { return footprint.idleSize }
        return CGSize(width: size.width + 2 * shoulder, height: height)
    }

    /// The closed body's height. A hardware notch hangs `belowNotch` below the notch so its whole bottom outline is
    /// seen; a drawn notch and the pill keep their own heights (the pill with wings is 30).
    public static func closedHeight(_ footprint: NotchFootprint, wings: ClosedWingsFacts?) -> CGFloat {
        let size = footprint.layoutSize
        let showsWings = (wings ?? .noWings).showsWings
        let base = showsWings ? max(size.height, 30) : (footprint.isPill ? footprint.idleSize.height : size.height)
        if case .hardware = footprint { return base + NotchClosedBodyLayout.belowNotch }
        return base
    }

    /// The closed body in screen coordinates: centred, hanging from the top offset.
    public static func bodyRect(_ footprint: NotchFootprint, screenFrame: CGRect, topOffset: CGFloat,
                                wings: ClosedWingsFacts?) -> CGRect {
        let size = closedSize(footprint, wings: wings)
        return CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - max(topOffset, 0) - size.height,
                      width: size.width, height: size.height)
    }

    /// The closed bar as the zones and the alert line under it see it: at least 30, plus the drop below a hardware notch.
    public static func closedBarHeight(_ footprint: NotchFootprint) -> CGFloat {
        let bar = max(footprint.layoutSize.height, 30)
        if case .hardware = footprint { return bar + NotchClosedBodyLayout.belowNotch }
        return bar
    }

    /// The island that opens the notch on hover. A drawn shape's zone is its body and nothing above it, so a lowered
    /// shape never claims the menu bar strip over it. The hardware notch and the pill keep their zones: at least
    /// 160 wide, as tall as the bar plus the drop, and with a wing kind showing both wings and their ears. A lit
    /// light alone widens the body and not those zones.
    public static func hoverZone(_ footprint: NotchFootprint, screenFrame: CGRect, topOffset: CGFloat,
                                 wings: ClosedWingsFacts?) -> CGRect {
        if case .drawn = footprint { return bodyRect(footprint, screenFrame: screenFrame, topOffset: topOffset, wings: wings) }
        let size = footprint.layoutSize
        var island = max(size.width, 160)
        if let wings, !wings.kindIsNone {
            island += 2 * (NotchClosedBodyLayout.wingWidth + 8 + wings.extraWidth)
        }
        return GlanceTopBar.hoverZone(screen: screenFrame, notch: CGSize(width: island, height: closedBarHeight(footprint) + topOffset))
    }

    /// Where a click opens the notch. A drawn shape's zone is its body; the other footprints ignore `wings`.
    public static func clickZone(_ footprint: NotchFootprint, screenFrame: CGRect, topOffset: CGFloat,
                                 wings: ClosedWingsFacts? = nil) -> CGRect {
        if case .drawn = footprint { return bodyRect(footprint, screenFrame: screenFrame, topOffset: topOffset, wings: wings) }
        var size = footprint.layoutSize
        if case .hardware = footprint, size.height > 0 { size.height += NotchClosedBodyLayout.belowNotch }
        return NotchOpenRules.clickZone(screenFrame: screenFrame, notchSize: size, topOffset: topOffset)
    }

    /// Whether the window takes the mouse at a point. A closed drawn notch takes it on its body. A hardware
    /// notch and the pill stay click-through until a wing kind is showing, so the play and pause control on
    /// those wings can receive the pointer. The top edge counts and the bottom does not, as in
    /// `GlanceTopBar.inHoverZone`.
    public static func takesMouse(_ footprint: NotchFootprint, closed: Bool, point: CGPoint, screenFrame: CGRect,
                                  topOffset: CGFloat, wings: ClosedWingsFacts?) -> Bool {
        guard closed else { return false }
        let onBody = pointIsOnClosedBody(footprint, point: point, screenFrame: screenFrame, topOffset: topOffset, wings: wings)
        if case .drawn = footprint { return onBody }
        guard let wings, !wings.kindIsNone else { return false }
        return onBody
    }

    private static func pointIsOnClosedBody(_ footprint: NotchFootprint, point: CGPoint, screenFrame: CGRect,
                                            topOffset: CGFloat, wings: ClosedWingsFacts?) -> Bool {
        let body = bodyRect(footprint, screenFrame: screenFrame, topOffset: topOffset, wings: wings)
        return abs(point.x - body.midX) <= body.width / 2 && point.y > body.minY && point.y <= body.maxY
    }
}
