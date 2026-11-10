import CoreGraphics
import Foundation

/// P0 item I: "Zeus next to the cursor". Pure geometry and follow-rate math (no AppKit) behind
/// the `presence.nearCursor` setting -- the AppKit side (global mouse monitor, panel
/// positioning) lives in Sources/Zeus/Overlay/CursorPresenceController.swift.
///
/// AppKit screen coordinates: origin bottom-left, y increases upward. "18 px right and 18 px
/// down from the pointer" is therefore `(+18, -18)`.
public enum CursorAnchor {
    public static let defaultOffset = CGPoint(x: 18, y: -18)
    /// Never closer than this to a caret rect (AX), so the window never covers text being typed.
    public static let defaultCaretMargin: CGFloat = 24

    /// The frame a `size`-sized window should take, anchored near `cursor`, kept fully inside
    /// `screenFrame` (that screen's visible frame), flipped to the opposite side of the pointer
    /// when the plain offset would run off an edge, and pushed clear of `caretRect` (if given)
    /// by at least `caretMargin`.
    public static func frame(cursor: CGPoint, size: CGSize, screenFrame: CGRect,
                              offset: CGPoint = defaultOffset, caretRect: CGRect? = nil,
                              caretMargin: CGFloat = defaultCaretMargin) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(origin: cursor, size: size) }
        guard screenFrame.width >= size.width, screenFrame.height >= size.height else {
            // The window doesn't fit this screen at all: centre it rather than produce a
            // negative-size or off-screen rect.
            return CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2, width: size.width, height: size.height)
        }
        // Down from the pointer means the box's *top* sits `offset.y` below the pointer, so the
        // bottom-left origin is a further `size.height` down.
        var origin = CGPoint(x: cursor.x + offset.x, y: cursor.y + offset.y - size.height)
        if origin.x + size.width > screenFrame.maxX {
            // Flip to the left of the pointer instead of the right.
            origin.x = cursor.x - offset.x - size.width
        }
        if origin.y < screenFrame.minY {
            // Flip to above the pointer instead of below it.
            origin.y = cursor.y - offset.y
        }
        var rect = CGRect(origin: origin, size: size)
        rect.origin.x = min(max(rect.origin.x, screenFrame.minX), screenFrame.maxX - size.width)
        rect.origin.y = min(max(rect.origin.y, screenFrame.minY), screenFrame.maxY - size.height)
        // Only dodge a caret that is actually near the pointer (QA round 14 E2E: a stale TextEdit
        // caret far from the test pointer pushed the pill ~125 px away and failed presence-near-300-300).
        let caretNear = caretRect.map { hypot($0.midX - cursor.x, $0.midY - cursor.y) <= 160 } ?? false
        if caretNear, let caretRect, rect.insetBy(dx: -caretMargin, dy: -caretMargin).intersects(caretRect) {
            let below = caretRect.minY - caretMargin - size.height
            if below >= screenFrame.minY {
                rect.origin.y = below
            } else {
                rect.origin.y = min(caretRect.maxY + caretMargin, screenFrame.maxY - size.height)
            }
        }
        return rect
    }

    /// Which display's frame the cursor is over (multi-display aware); falls back to the given
    /// main frame, then the first screen, so there is always somewhere to anchor within even if
    /// the cursor briefly reads a stale position between display changes.
    public static func screenFrame(containing cursor: CGPoint, screens: [CGRect], main: CGRect?) -> CGRect {
        if let match = screens.first(where: { $0.contains(cursor) }) { return match }
        if let main { return main }
        return screens.first ?? .zero
    }

    /// `frame(cursor:size:screenFrame:...)` above returns AppKit screen coordinates (origin
    /// bottom-left of the *main* screen, y increases upward) -- correct and required for
    /// `NSPanel.setFrameOrigin`. External tools (screenshots, synthetic mouse events, `zeus
    /// debug`) all work in Quartz/CG global display coordinates (origin top-left of the main
    /// screen, y increases downward), the same convention `AXSnapshot` frames already document.
    /// This flip is self-inverse (same formula either direction, like `CaretLocator`'s AX-bounds
    /// flip): converts one rect between the two, given the main screen's height in points.
    public static func flipToQuartz(_ rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x, y: mainScreenHeight - rect.origin.y - rect.height, width: rect.width, height: rect.height)
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
        !isActiveDictation
    }
}

public enum SpringFollow {
    public static let defaultRate = 28.0

    public static func step(current: CGPoint, target: CGPoint, dt: Double, rate: Double = defaultRate) -> CGPoint {
        guard dt.isFinite, dt > 0 else { return current }
        let k = 1 - exp(-dt * rate)
        return CGPoint(x: current.x + (target.x - current.x) * k, y: current.y + (target.y - current.y) * k)
    }

    public static func isSettled(current: CGPoint, target: CGPoint, epsilon: Double = 0.25) -> Bool {
        hypot(target.x - current.x, target.y - current.y) <= epsilon
    }
}
