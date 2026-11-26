import CoreGraphics
import Foundation

/// P0 item I: "Zeus next to the cursor". Pure geometry and follow-rate math (no AppKit) behind
/// the `presence.nearCursor` setting -- the AppKit side (global mouse monitor, panel
/// positioning) lives in Sources/Zeus/Overlay/CursorPresenceController.swift.
///
/// AppKit screen coordinates: origin bottom-left, y increases upward. "18 px right and 18 px
/// down from the pointer" is therefore `(+18, -18)`.
/// The arithmetic lives in `CursorPresenceBox`.
public enum CursorAnchor {
    public static let defaultOffset = CGPoint(x: CGFloat(CursorAnchorBox.defaultOffset.x),
                                               y: CGFloat(CursorAnchorBox.defaultOffset.y))
    /// Never closer than this to a caret rect (AX), so the window never covers text being typed.
    public static let defaultCaretMargin: CGFloat = CGFloat(CursorAnchorBox.defaultCaretMargin)

    /// The frame a `size`-sized window should take, anchored near `cursor`, kept fully inside
    /// `screenFrame` (that screen's visible frame), flipped to the opposite side of the pointer
    /// when the plain offset would run off an edge, and pushed clear of `caretRect` (if given)
    /// by at least `caretMargin`.
    public static func frame(cursor: CGPoint, size: CGSize, screenFrame: CGRect,
                              offset: CGPoint = defaultOffset, caretRect: CGRect? = nil,
                              caretMargin: CGFloat = defaultCaretMargin) -> CGRect {
        cgRect(CursorAnchorBox.frame(cursor: boxPoint(cursor), size: boxSize(size), screenFrame: boxRect(screenFrame),
                                      offset: boxPoint(offset), caretRect: caretRect.map(boxRect),
                                      caretMargin: Double(caretMargin)))
    }

    /// Which display's frame the cursor is over (multi-display aware); falls back to the given
    /// main frame, then the first screen, so there is always somewhere to anchor within even if
    /// the cursor briefly reads a stale position between display changes.
    public static func screenFrame(containing cursor: CGPoint, screens: [CGRect], main: CGRect?) -> CGRect {
        cgRect(CursorAnchorBox.screenFrame(containing: boxPoint(cursor), screens: screens.map(boxRect),
                                            main: main.map(boxRect)))
    }

    /// `frame(cursor:size:screenFrame:...)` above returns AppKit screen coordinates (origin
    /// bottom-left of the *main* screen, y increases upward) -- correct and required for
    /// `NSPanel.setFrameOrigin`. External tools (screenshots, synthetic mouse events, `zeus
    /// debug`) all work in Quartz/CG global display coordinates (origin top-left of the main
    /// screen, y increases downward), the same convention `AXSnapshot` frames already document.
    /// This flip is self-inverse (same formula either direction, like `CaretLocator`'s AX-bounds
    /// flip): converts one rect between the two, given the main screen's height in points.
    public static func flipToQuartz(_ rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        cgRect(CursorAnchorBox.flipToQuartz(boxRect(rect), mainScreenHeight: Double(mainScreenHeight)))
    }
}

/// The exponential "ease toward target" `BuddyController.tick()` already uses
/// (`1 - exp(-dt * rate)`), pulled out as pure, unit-testable steps so another cursor-following
/// presence window (the dictation pill) can reuse the exact same no-jitter follow feel without
/// duplicating or diverging from it.
/// When the dictation pill auto-hides after a turn, a delayed task must not tear down cursor
/// presence if a new hold-to-speak turn already started (E2E `presence-near-*` runs three
/// back-to-back talk-key holds; a stale hide fired after the third `track()` left
/// `tracking:false` / `frame:null`).
public enum CursorPresenceGuard {
    public static func delayedPillHideShouldStopPresence(isActiveDictation: Bool) -> Bool {
        CursorPresenceGuardBox.delayedPillHideShouldStopPresence(isActiveDictation: isActiveDictation)
    }
}

public enum SpringFollow {
    public static let defaultRate = SpringFollowBox.defaultRate

    public static func step(current: CGPoint, target: CGPoint, dt: Double, rate: Double = defaultRate) -> CGPoint {
        cgPoint(SpringFollowBox.step(current: boxPoint(current), target: boxPoint(target), dt: dt, rate: rate))
    }

    public static func isSettled(current: CGPoint, target: CGPoint, epsilon: Double = 0.25) -> Bool {
        SpringFollowBox.isSettled(current: boxPoint(current), target: boxPoint(target), epsilon: epsilon)
    }
}

private func boxPoint(_ point: CGPoint) -> CursorAnchorBox.Point {
    CursorAnchorBox.Point(x: Double(point.x), y: Double(point.y))
}

private func boxSize(_ size: CGSize) -> CursorAnchorBox.Size {
    CursorAnchorBox.Size(width: Double(size.width), height: Double(size.height))
}

private func boxRect(_ rect: CGRect) -> CursorAnchorBox.Rect {
    CursorAnchorBox.Rect(x: Double(rect.origin.x), y: Double(rect.origin.y),
                         width: Double(rect.width), height: Double(rect.height))
}

private func cgPoint(_ point: CursorAnchorBox.Point) -> CGPoint {
    CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
}

private func cgRect(_ rect: CursorAnchorBox.Rect) -> CGRect {
    CGRect(x: CGFloat(rect.x), y: CGFloat(rect.y), width: CGFloat(rect.width), height: CGFloat(rect.height))
}
