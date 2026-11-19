import CoreGraphics
import Foundation

/// The box a hover open is allowed to occupy. A notification, an approval, Scribe or now playing
/// may sit inside that box. None of them may add their own height to it.
public enum NotchLayoutBounds {
    /// The wide page, ears included.
    public static var maxWidth: CGFloat { GlanceTopBar.panelSize(home: false).width }
    /// The tall page, with nothing stacked under it.
    public static var maxHeight: CGFloat { GlanceTopBar.panelSize(home: false).height }

    public struct Factors: Equatable, Sendable, CustomStringConvertible {
        public var hover: Bool
        public var home: Bool
        public var notification: Bool
        public var approval: Bool
        public var approvalExtra: CGFloat
        public var scribe: Bool
        public var nowPlaying: Bool
        public var homeStrip: CGFloat
        public var sessionCount: Int

        public init(hover: Bool, home: Bool = true, notification: Bool = false, approval: Bool = false,
                    approvalExtra: CGFloat = 0, scribe: Bool = false, nowPlaying: Bool = false,
                    homeStrip: CGFloat = 0, sessionCount: Int = 0) {
            self.hover = hover
            self.home = home
            self.notification = notification
            self.approval = approval
            self.approvalExtra = approvalExtra
            self.scribe = scribe
            self.nowPlaying = nowPlaying
            self.homeStrip = homeStrip
            self.sessionCount = sessionCount
        }

        public var description: String {
            "hover \(hover) home \(home) note \(notification) approval \(approval) extra \(approvalExtra) scribe \(scribe) playing \(nowPlaying) strip \(homeStrip) sessions \(sessionCount)"
        }
    }

    /// Every flag the panel can combine. Approval content is deliberately large so a leak fails the bound.
    public static var combinations: [Factors] {
        var all: [Factors] = []
        for hover in [false, true] {
            for notification in [false, true] {
                for approval in [false, true] {
                    for scribe in [false, true] {
                        for playing in [false, true] {
                            all.append(Factors(hover: hover, home: !scribe && !playing, notification: notification,
                                               approval: approval, approvalExtra: approval ? 480 : 0,
                                               scribe: scribe, nowPlaying: playing,
                                               homeStrip: HomeStrip.height + HomeStrip.gap, sessionCount: 8))
                        }
                    }
                }
            }
        }
        return all
    }

    public static func size(_ factors: Factors) -> CGSize {
        let homePage = factors.home && !factors.scribe && !factors.nowPlaying
        if factors.hover {
            let strip = homePage ? min(max(factors.homeStrip, 0), HomeStrip.height + HomeStrip.gap) : 0
            return clamp(GlanceTopBar.panelSize(home: homePage, extra: strip))
        }
        let showingCard = factors.notification || factors.approval
        let width: CGFloat = showingCard ? 520 : GlanceTopBar.closedSize.width
        let height: CGFloat = showingCard ? 152 : GlanceTopBar.closedSize.height
        return clamp(CGSize(width: width, height: height))
    }

    public static func clamp(_ size: CGSize) -> CGSize {
        CGSize(width: min(max(size.width, 1), maxWidth), height: min(max(size.height, 1), maxHeight))
    }
}
