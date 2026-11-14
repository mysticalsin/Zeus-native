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

/// The shape the closed notch takes on one display: the hardware notch, or the slim pill where there is none.
public enum NotchFootprint: Sendable, Equatable {
    case hardware(CGSize)
    case pill

    /// The hardware size, and zero for the pill: what the layout calls the notch.
    public var layoutSize: CGSize {
        switch self {
        case .hardware(let size): size
        case .pill: .zero
        }
    }

    /// The closed, idle shape.
    public var idleSize: CGSize {
        switch self {
        case .hardware(let size): size
        case .pill: NotchClosedBodyLayout.slimPillSize
        }
    }

    /// The width the wings grow from.
    public var wingBase: CGFloat {
        switch self {
        case .hardware(let size): size.width
        case .pill: 40
        }
    }

    public var isPill: Bool {
        if case .pill = self { return true }
        return false
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

    /// The island that opens the notch on hover: at least 160 wide, as tall as the bar plus the drop, and with a wing
    /// kind showing both wings and their ears. A lit light alone widens the body and not this zone.
    public static func hoverZone(_ footprint: NotchFootprint, screenFrame: CGRect, topOffset: CGFloat,
                                 wings: ClosedWingsFacts?) -> CGRect {
        let size = footprint.layoutSize
        var island = max(size.width, 160)
        if let wings, !wings.kindIsNone {
            island += 2 * (NotchClosedBodyLayout.wingWidth + 8) + wings.extraWidth
        }
        return GlanceTopBar.hoverZone(screen: screenFrame, notch: CGSize(width: island, height: max(size.height, 30) + topOffset))
    }

    public static func clickZone(_ footprint: NotchFootprint, screenFrame: CGRect, topOffset: CGFloat) -> CGRect {
        NotchOpenRules.clickZone(screenFrame: screenFrame, notchSize: footprint.layoutSize, topOffset: topOffset)
    }
}
