import Foundation

/// Peek bar height. The closed bar keeps `max(notch, 30)`. A peek grows with the scaled title
/// so an accessibility size of 32.4 pt is not clipped by the 30 pt floor.
public enum NotchPeekFit {
    public static let closedMinimum: Double = 30

    public static func barHeight(notchHeight: Double, scaledFont: Double, peeking: Bool) -> Double {
        let closed = max(notchHeight, closedMinimum)
        guard peeking else { return closed }
        return max(closed, scaledFont)
    }
}
