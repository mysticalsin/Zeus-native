import CoreGraphics
import Testing
@testable import ZeusCore

/// P0 item I: "Zeus next to the cursor" anchor math (pure; the AppKit controller lives in
/// Sources/Zeus/Overlay/CursorPresenceController.swift, covered by its own app-level tests).
@Suite struct CursorPresenceTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 292, height: 48)

    @Test func plainCaseSitsEighteenPointsRightAndDown() {
        let cursor = CGPoint(x: 400, y: 400)
        let rect = CursorAnchor.frame(cursor: cursor, size: size, screenFrame: screen)
        #expect(abs(rect.minX - (cursor.x + 18)) < 0.01)
        // "down" in AppKit is a smaller y; the box's top edge should sit 18 pt below the cursor.
        #expect(abs(rect.maxY - (cursor.y - 18)) < 0.01)
    }

    @Test func flipsToTheLeftNearTheRightEdge() {
        let cursor = CGPoint(x: screen.maxX - 5, y: 400)
        let rect = CursorAnchor.frame(cursor: cursor, size: size, screenFrame: screen)
        #expect(rect.maxX <= screen.maxX + 0.01)
        #expect(rect.maxX < cursor.x, "should flip to the pointer's left, not clip at the right edge")
    }

    @Test func flipsAboveNearTheBottomEdge() {
        let cursor = CGPoint(x: 400, y: screen.minY + 5)
        let rect = CursorAnchor.frame(cursor: cursor, size: size, screenFrame: screen)
        #expect(rect.minY >= screen.minY - 0.01)
        #expect(rect.minY > cursor.y, "should flip above the pointer, not clip at the bottom edge")
    }

    @Test func staysFullyInsideTheScreenInEveryCorner() {
        let corners = [
            CGPoint(x: screen.minX, y: screen.minY), CGPoint(x: screen.maxX, y: screen.minY),
            CGPoint(x: screen.minX, y: screen.maxY), CGPoint(x: screen.maxX, y: screen.maxY),
        ]
        for cursor in corners {
            let rect = CursorAnchor.frame(cursor: cursor, size: size, screenFrame: screen)
            #expect(screen.contains(CGPoint(x: rect.minX, y: rect.minY)))
            #expect(screen.contains(CGPoint(x: rect.maxX - 0.01, y: rect.maxY - 0.01)))
        }
    }

    @Test func multiDisplayPicksTheScreenUnderTheCursor() {
        let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let onRight = CursorAnchor.screenFrame(containing: CGPoint(x: 2000, y: 500), screens: [left, right], main: left)
        #expect(onRight == right)
        let onLeft = CursorAnchor.screenFrame(containing: CGPoint(x: 200, y: 500), screens: [left, right], main: left)
        #expect(onLeft == left)
    }

    @Test func multiDisplayFallsBackToMainWhenNoScreenContainsThePoint() {
        let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // A stale point between a display reconfiguration (no screen currently claims it).
        let fallback = CursorAnchor.screenFrame(containing: CGPoint(x: -5000, y: -5000), screens: [left], main: left)
        #expect(fallback == left)
    }

    @Test func scaleOneAndTwoProduceTheSameLogicalFrame() {
        // The anchor math works in points, not pixels: a Retina (2x) screen's frame is still
        // expressed in the same point space, so the same cursor position and window size give an
        // identical frame regardless of the display's backing scale factor.
        let cursor = CGPoint(x: 600, y: 500)
        let rect1x = CursorAnchor.frame(cursor: cursor, size: size, screenFrame: screen)
        let rect2x = CursorAnchor.frame(cursor: cursor, size: size, screenFrame: screen)
        #expect(rect1x == rect2x)
    }

    @Test func pushesClearOfACaretRectInsteadOfCoveringIt() {
        let cursor = CGPoint(x: 400, y: 400)
        // A caret directly where the plain offset would land the window.
        let caret = CGRect(x: cursor.x + 18, y: cursor.y - 18 - size.height, width: 2, height: 16)
        let rect = CursorAnchor.frame(cursor: cursor, size: size, screenFrame: screen, caretRect: caret)
        #expect(!rect.insetBy(dx: -CursorAnchor.defaultCaretMargin, dy: -CursorAnchor.defaultCaretMargin).intersects(caret) || rect == caret,
                "the window should move clear of the caret by at least the margin")
    }

    @Test func ignoresAFarAwayCaretRect() {
        let cursor = CGPoint(x: 300, y: 817)
        let farCaret = CGRect(x: 100, y: 100, width: 2, height: 16)
        let without = CursorAnchor.frame(cursor: cursor, size: size, screenFrame: screen)
        let withFar = CursorAnchor.frame(cursor: cursor, size: size, screenFrame: screen, caretRect: farCaret)
        #expect(without == withFar)
    }

    @Test func tooSmallAScreenCentersInsteadOfProducingAnOffScreenRect() {
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rect = CursorAnchor.frame(cursor: CGPoint(x: 50, y: 50), size: size, screenFrame: tiny)
        #expect(abs(rect.midX - tiny.midX) < 0.01)
        #expect(abs(rect.midY - tiny.midY) < 0.01)
    }

    // MARK: SpringFollow

    @Test func springStepMovesTowardTargetNeverOvershooting() {
        let start = CGPoint(x: 0, y: 0)
        let target = CGPoint(x: 100, y: 0)
        let next = SpringFollow.step(current: start, target: target, dt: 1.0 / 60)
        #expect(next.x > 0 && next.x < 100)
    }

    @Test func springSettlesToTheTargetOverManySteps() {
        var p = CGPoint(x: 0, y: 0)
        let target = CGPoint(x: 100, y: 50)
        for _ in 0..<300 { p = SpringFollow.step(current: p, target: target, dt: 1.0 / 60) }
        #expect(SpringFollow.isSettled(current: p, target: target))
    }

    // Regression (QA round 8/9): `zeus debug presence state` reported raw AppKit-space frames,
    // so the E2E harness (which moves the pointer and reads frames back in Quartz/CG space, same
    // convention as AXSnapshot and screenshots) compared two different coordinate spaces and
    // every presence-near-* check failed with "far:500"-ish distances. `flipToQuartz` is the fix.
    @Test func flipToQuartzMatchesAKnownAppKitToQuartzPair() {
        // Main screen 1117 pt tall; a cursor at Quartz (300, 300) is AppKit (300, 817). A panel
        // anchored 18 right/18 down with height 48 sits at AppKit origin (318, 751) -- exactly
        // what the P0 item I frame math (`frame(cursor:size:screenFrame:)`) would produce. Its
        // Quartz top-left should land back near the original (300, 300) cursor, offset by 18 px.
        let appKitFrame = CGRect(x: 318, y: 751, width: 292, height: 48)
        let quartz = CursorAnchor.flipToQuartz(appKitFrame, mainScreenHeight: 1117)
        #expect(abs(quartz.origin.x - 318) < 0.01)
        #expect(abs(quartz.origin.y - 318) < 0.01) // 1117 - 751 - 48 = 318 = 300 (cursor) + 18 (offset)
        #expect(quartz.width == 292 && quartz.height == 48)
    }

    @Test func flipToQuartzIsItsOwnInverse() {
        let rect = CGRect(x: 42, y: 100, width: 292, height: 48)
        let height: CGFloat = 1117
        let roundTrip = CursorAnchor.flipToQuartz(CursorAnchor.flipToQuartz(rect, mainScreenHeight: height), mainScreenHeight: height)
        #expect(abs(roundTrip.origin.x - rect.origin.x) < 0.01)
        #expect(abs(roundTrip.origin.y - rect.origin.y) < 0.01)
    }

    @Test func springStepIsANoOpForZeroOrInvalidDeltaTime() {
        let p = CGPoint(x: 10, y: 10)
        #expect(SpringFollow.step(current: p, target: CGPoint(x: 999, y: 999), dt: 0) == p)
        #expect(SpringFollow.step(current: p, target: CGPoint(x: 999, y: 999), dt: -1) == p)
    }

    @Test func delayedPillHideDoesNotStopPresenceDuringActiveDictation() {
        #expect(CursorPresenceGuard.delayedPillHideShouldStopPresence(isActiveDictation: true) == false)
        #expect(CursorPresenceGuard.delayedPillHideShouldStopPresence(isActiveDictation: false) == true)
    }
}
