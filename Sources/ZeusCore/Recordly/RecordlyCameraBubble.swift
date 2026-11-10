import Foundation

/// Webcam bubble scale: grows when the pointer is idle, shrinks during motion (pure math).
public enum RecordlyCameraBubbleScale {
    public static let idleAfter: Double = 1.2
    public static let idleScale: Double = 1.15
    public static let activeScale: Double = 0.82

    public static func scale(lastMove: Double, now: Double, moving: Bool) -> Double {
        if moving { return activeScale }
        if now - lastMove >= idleAfter { return idleScale }
        let t = min(max((now - lastMove) / idleAfter, 0), 1)
        return activeScale + (idleScale - activeScale) * t
    }
}
