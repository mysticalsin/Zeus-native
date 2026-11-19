import CoreGraphics

/// While a peek (approval, completion, trouble, recap) is up, the full-width notch window takes the mouse only over
/// the visible card and a few points around it. The rest of the 470 pt strip stays click-through, so a pending
/// choice never blocks the app underneath. AppKit coordinates (origin bottom-left).
public enum NotchPeekHitRules {
    /// Room past the card so the edge is easy to hit.
    public static let slack: CGFloat = 6

    /// The card as drawn: centred on the screen, hanging from the top offset.
    public static func cardRect(size: CGSize, screenFrame: CGRect, topOffset: CGFloat) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - max(topOffset, 0) - size.height,
               width: size.width, height: size.height)
    }

    public static func takesMouse(_ point: CGPoint, size: CGSize, screenFrame: CGRect, topOffset: CGFloat,
                                  slack: CGFloat = slack) -> Bool {
        cardRect(size: size, screenFrame: screenFrame, topOffset: topOffset)
            .insetBy(dx: -slack, dy: -slack).contains(point)
    }
}
