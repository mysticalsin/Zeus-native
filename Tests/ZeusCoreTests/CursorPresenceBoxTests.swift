import Foundation
import Testing
@testable import ZeusCore

/// Double geometry for the cursor pill. The AppKit panel stays in `CursorPresenceController`.
@Suite struct CursorPresenceBoxTests {
    private let screen = CursorAnchorBox.Rect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CursorAnchorBox.Size(width: 292, height: 48)

    @Test func plainOffsetSitsEighteenPointsRightAndDown() {
        #expect(CursorAnchorBox.defaultOffset == CursorAnchorBox.Point(x: 18, y: -18))
        #expect(CursorAnchorBox.defaultCaretMargin == 24)
        let cursor = CursorAnchorBox.Point(x: 400, y: 400)
        let rect = CursorAnchorBox.frame(cursor: cursor, size: size, screenFrame: screen)
        #expect(abs(rect.minX - 418) < 0.01)
        #expect(abs(rect.maxY - 382) < 0.01)
        #expect(rect.width == 292 && rect.height == 48)
    }

    @Test func theWindowFlipsLeftOfACursorOnTheRightEdge() {
        let cursor = CursorAnchorBox.Point(x: screen.maxX - 5, y: 400)
        let rect = CursorAnchorBox.frame(cursor: cursor, size: size, screenFrame: screen)
        #expect(abs(rect.minX - 1125) < 0.01)
        #expect(abs(rect.minY - 334) < 0.01)
        #expect(rect.maxX < cursor.x)
        #expect(rect.maxX <= screen.maxX + 0.01)
    }

    @Test func theWindowFlipsAboveACursorOnTheBottomEdge() {
        let cursor = CursorAnchorBox.Point(x: 400, y: screen.minY + 5)
        let rect = CursorAnchorBox.frame(cursor: cursor, size: size, screenFrame: screen)
        #expect(abs(rect.minX - 418) < 0.01)
        #expect(abs(rect.minY - 23) < 0.01)
        #expect(rect.minY > cursor.y)
        #expect(rect.minY >= screen.minY - 0.01)
    }

    @Test func everyCornerKeepsTheWindowInsideTheScreen() {
        let expected: [(CursorAnchorBox.Point, Double, Double)] = [
            (CursorAnchorBox.Point(x: 0, y: 0), 18, 18),
            (CursorAnchorBox.Point(x: 1440, y: 0), 1130, 18),
            (CursorAnchorBox.Point(x: 0, y: 900), 18, 834),
            (CursorAnchorBox.Point(x: 1440, y: 900), 1130, 834),
        ]
        for (cursor, x, y) in expected {
            let rect = CursorAnchorBox.frame(cursor: cursor, size: size, screenFrame: screen)
            #expect(abs(rect.x - x) < 0.01)
            #expect(abs(rect.y - y) < 0.01)
            #expect(screen.contains(CursorAnchorBox.Point(x: rect.minX, y: rect.minY)))
            #expect(screen.contains(CursorAnchorBox.Point(x: rect.maxX - 0.01, y: rect.maxY - 0.01)))
        }
    }

    @Test func theScreenUnderTheCursorWinsAndAFarEdgeFallsBack() {
        let left = CursorAnchorBox.Rect(x: 0, y: 0, width: 1440, height: 900)
        let right = CursorAnchorBox.Rect(x: 1440, y: 0, width: 1920, height: 1080)
        let onRight = CursorAnchorBox.screenFrame(containing: CursorAnchorBox.Point(x: 2000, y: 500), screens: [left, right], main: left)
        #expect(onRight == right)
        let onSharedEdge = CursorAnchorBox.screenFrame(containing: CursorAnchorBox.Point(x: 1440, y: 500), screens: [left, right], main: left)
        #expect(onSharedEdge == right)
        let onLeft = CursorAnchorBox.screenFrame(containing: CursorAnchorBox.Point(x: 200, y: 500), screens: [left, right], main: left)
        #expect(onLeft == left)
        let missed = CursorAnchorBox.screenFrame(containing: CursorAnchorBox.Point(x: -5000, y: -5000), screens: [left], main: left)
        #expect(missed == left)
        let farEdge = CursorAnchorBox.screenFrame(containing: CursorAnchorBox.Point(x: 3360, y: 500), screens: [left, right], main: left)
        #expect(farEdge == left)
        let first = CursorAnchorBox.screenFrame(containing: CursorAnchorBox.Point(x: -1, y: -1), screens: [right], main: nil)
        #expect(first == right)
        let none = CursorAnchorBox.screenFrame(containing: CursorAnchorBox.Point(x: 1, y: 1), screens: [], main: nil)
        #expect(none == CursorAnchorBox.Rect(x: 0, y: 0, width: 0, height: 0))
    }

    @Test func aNearCaretMovesClearAndAFarCaretDoesNot() {
        let cursor = CursorAnchorBox.Point(x: 400, y: 400)
        let caret = CursorAnchorBox.Rect(x: cursor.x + 18, y: cursor.y - 18 - size.height, width: 2, height: 16)
        let rect = CursorAnchorBox.frame(cursor: cursor, size: size, screenFrame: screen, caretRect: caret)
        #expect(abs(rect.x - 418) < 0.01)
        #expect(abs(rect.y - 262) < 0.01)
        let grown = rect.insetBy(dx: -CursorAnchorBox.defaultCaretMargin, dy: -CursorAnchorBox.defaultCaretMargin)
        #expect(!grown.intersects(caret))

        let lowCursor = CursorAnchorBox.Point(x: 400, y: 80)
        let lowCaret = CursorAnchorBox.Rect(x: 418, y: 14, width: 2, height: 16)
        let lifted = CursorAnchorBox.frame(cursor: lowCursor, size: size, screenFrame: screen, caretRect: lowCaret)
        #expect(abs(lifted.y - 54) < 0.01)

        let elsewhere = CursorAnchorBox.Point(x: 300, y: 817)
        let far = CursorAnchorBox.Rect(x: 100, y: 100, width: 2, height: 16)
        let plain = CursorAnchorBox.frame(cursor: elsewhere, size: size, screenFrame: screen)
        let withFar = CursorAnchorBox.frame(cursor: elsewhere, size: size, screenFrame: screen, caretRect: far)
        #expect(plain == withFar)
        #expect(abs(plain.x - 318) < 0.01)
        #expect(abs(plain.y - 751) < 0.01)
    }

    @Test func aScreenTooSmallCentersAndAFlatSizeStaysOnTheCursor() {
        let tiny = CursorAnchorBox.Rect(x: 0, y: 0, width: 100, height: 100)
        let rect = CursorAnchorBox.frame(cursor: CursorAnchorBox.Point(x: 50, y: 50), size: size, screenFrame: tiny)
        #expect(abs(rect.midX - 50) < 0.01)
        #expect(abs(rect.midY - 50) < 0.01)
        #expect(rect.width == 292 && rect.height == 48)
        let flat = CursorAnchorBox.frame(
            cursor: CursorAnchorBox.Point(x: 50, y: 50),
            size: CursorAnchorBox.Size(width: 0, height: 48),
            screenFrame: screen)
        #expect(flat == CursorAnchorBox.Rect(x: 50, y: 50, width: 0, height: 48))
    }

    @Test func quartzFlipRoundTripsTheKnownPanel() {
        let appKit = CursorAnchorBox.Rect(x: 318, y: 751, width: 292, height: 48)
        let quartz = CursorAnchorBox.flipToQuartz(appKit, mainScreenHeight: 1117)
        #expect(abs(quartz.x - 318) < 0.01)
        #expect(abs(quartz.y - 318) < 0.01)
        #expect(quartz.width == 292 && quartz.height == 48)
        let rect = CursorAnchorBox.Rect(x: 42, y: 100, width: 292, height: 48)
        let roundTrip = CursorAnchorBox.flipToQuartz(CursorAnchorBox.flipToQuartz(rect, mainScreenHeight: 1117), mainScreenHeight: 1117)
        #expect(abs(roundTrip.x - rect.x) < 0.01)
        #expect(abs(roundTrip.y - rect.y) < 0.01)
    }

    @Test func springMovesTowardTheTargetAndABadStepStaysPut() {
        #expect(SpringFollowBox.defaultRate == 28)
        let next = SpringFollowBox.step(
            current: CursorAnchorBox.Point(x: 0, y: 0),
            target: CursorAnchorBox.Point(x: 100, y: 0),
            dt: 1.0 / 60)
        #expect(next.x > 30 && next.x < 45)
        #expect(next.y == 0)
        #expect(!SpringFollowBox.isSettled(current: next, target: CursorAnchorBox.Point(x: 100, y: 0)))
        var point = CursorAnchorBox.Point(x: 0, y: 0)
        let target = CursorAnchorBox.Point(x: 100, y: 50)
        for _ in 0..<300 {
            point = SpringFollowBox.step(current: point, target: target, dt: 1.0 / 60)
        }
        #expect(SpringFollowBox.isSettled(current: point, target: target))
        let stayed = CursorAnchorBox.Point(x: 10, y: 10)
        let gone = CursorAnchorBox.Point(x: 999, y: 999)
        #expect(SpringFollowBox.step(current: stayed, target: gone, dt: 0) == stayed)
        #expect(SpringFollowBox.step(current: stayed, target: gone, dt: -1) == stayed)
        #expect(SpringFollowBox.step(current: stayed, target: gone, dt: .nan) == stayed)
        #expect(SpringFollowBox.step(current: stayed, target: gone, dt: .infinity) == stayed)
    }

    @Test func aHideDuringDictationDoesNotStopPresence() {
        #expect(CursorPresenceGuardBox.delayedPillHideShouldStopPresence(isActiveDictation: true) == false)
        #expect(CursorPresenceGuardBox.delayedPillHideShouldStopPresence(isActiveDictation: false) == true)
    }
}
