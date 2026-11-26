import CoreGraphics

/// While a peek (approval, completion, trouble, recap) is up, the full-width notch window takes the mouse only over
/// the visible card and a few points around it. The rest of the 470 pt strip stays click-through, so a pending
/// choice never blocks the app underneath. AppKit coordinates (origin bottom-left).
public enum NotchPeekHitRules {
    /// Room past the card so the edge is easy to hit.
    public static let slack: CGFloat = CGFloat(NotchPeekHitRulesBox.slack)

    /// The card as drawn: centred on the screen, hanging from the top offset.
    public static func cardRect(size: CGSize, screenFrame: CGRect, topOffset: CGFloat) -> CGRect {
        let rect = NotchPeekHitRulesBox.cardRect(
            width: Double(size.width), height: Double(size.height),
            screenMinX: Double(screenFrame.minX), screenWidth: Double(screenFrame.width),
            screenMaxY: Double(screenFrame.maxY), topOffset: Double(topOffset))
        return CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    public static func takesMouse(_ point: CGPoint, size: CGSize, screenFrame: CGRect, topOffset: CGFloat,
                                  slack: CGFloat = slack) -> Bool {
        NotchPeekHitRulesBox.takesMouse(
            x: Double(point.x), y: Double(point.y),
            width: Double(size.width), height: Double(size.height),
            screenMinX: Double(screenFrame.minX), screenWidth: Double(screenFrame.width),
            screenMaxY: Double(screenFrame.maxY), topOffset: Double(topOffset), slack: Double(slack))
    }
}
