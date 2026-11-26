import Foundation
import Testing
@testable import ZeusCore

@Suite("Top bar position box")
struct TopBarPositionBoxTests {
    @Test func theSliderRangeIsFlushToTwentyFourOnATwoPointStep() {
        #expect(TopBarPositionBox.minimum == 0)
        #expect(TopBarPositionBox.maximum == 24)
        #expect(TopBarPositionBox.step == 2)
    }

    @Test func noDropUntilTheOwnerMovesTheSlider() {
        #expect(TopBarPositionBox.resolved(chosen: nil) == 0)
        #expect(TopBarPositionBox.applied(resolved: TopBarPositionBox.resolved(chosen: nil), panelOpen: false) == 0)
    }

    @Test func aChosenValueSnapsOntoTheStep() {
        #expect(TopBarPositionBox.clamped(0) == 0)
        #expect(TopBarPositionBox.clamped(16) == 16)
        #expect(TopBarPositionBox.resolved(chosen: 16) == 16)
        #expect(TopBarPositionBox.clamped(1) == 2)
        #expect(TopBarPositionBox.resolved(chosen: 7) == 8)
        #expect(TopBarPositionBox.clamped(23) == 24)
    }

    @Test func aValuePastTheEndsIsClamped() {
        #expect(TopBarPositionBox.clamped(99) == 24)
        #expect(TopBarPositionBox.resolved(chosen: 99) == 24)
        #expect(TopBarPositionBox.clamped(-5) == 0)
        #expect(TopBarPositionBox.resolved(chosen: -1) == 0)
        #expect(TopBarPositionBox.applied(resolved: 60, panelOpen: false) == 24)
    }

    @Test func aValueThatIsNotFiniteReadsAsNoDrop() {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            #expect(TopBarPositionBox.clamped(value) == 0)
            #expect(TopBarPositionBox.resolved(chosen: value) == 0)
            #expect(TopBarPositionBox.applied(resolved: value, panelOpen: false) == 0)
        }
    }

    @Test func theOpenPanelNeverDrops() {
        #expect(TopBarPositionBox.applied(resolved: 12, panelOpen: true) == 0)
        #expect(TopBarPositionBox.applied(resolved: 24, panelOpen: true) == 0)
        #expect(TopBarPositionBox.applied(resolved: 99, panelOpen: true) == 0)
        #expect(TopBarPositionBox.applied(resolved: .nan, panelOpen: true) == 0)
        #expect(TopBarPositionBox.applied(resolved: 12, panelOpen: false) == 12)
    }

    @Test func ordinaryScreenHugsThePhysicalEdge() {
        let outline = TopBarPositionBox.outline(width: 1512, height: 982)
        #expect(TopBarPositionBox.edgeInset == 2)
        #expect(TopBarPositionBox.edgeRadius == 12)
        #expect(outline == TopBarPositionBox.Outline(
            centerX: 756, top: 2, right: 1510, bottom: 980, radius: 12
        ))
    }

    @Test func theCornerFitsATinyScreen() {
        let tiny = TopBarPositionBox.outline(width: 10, height: 10)
        #expect(tiny == TopBarPositionBox.Outline(
            centerX: 5, top: 2, right: 8, bottom: 8, radius: 3
        ))
        #expect(tiny.radius <= tiny.right - tiny.centerX)
        #expect(tiny.radius <= (tiny.bottom - tiny.top) / 2)
    }

    @Test func aRadiusLargerThanTheRoomIsClamped() {
        let fitted = TopBarPositionBox.outline(width: 100, height: 80, inset: 10, radius: 40)
        #expect(fitted.centerX == 50)
        #expect(fitted.top == 10)
        #expect(fitted.right == 90)
        #expect(fitted.bottom == 70)
        #expect(fitted.radius == 30)
    }

    @Test func aBadSizeReadsAsNoCorner() {
        let bad = TopBarPositionBox.outline(width: .nan, height: -4)
        #expect(bad == TopBarPositionBox.Outline(
            centerX: 0, top: 2, right: 0, bottom: 2, radius: 0
        ))
        #expect(bad.right >= bad.centerX)
        #expect(bad.bottom >= bad.top)
        let negative = TopBarPositionBox.outline(width: -20, height: 900)
        #expect(negative.centerX == 0)
        #expect(negative.radius == 0)
        #expect(negative.right >= negative.centerX)
    }

    @Test func anInsetThatIsNotFiniteSitsFlush() {
        let flush = TopBarPositionBox.outline(width: 1512, height: 982, inset: .nan, radius: 12)
        #expect(flush == TopBarPositionBox.Outline(
            centerX: 756, top: 0, right: 1512, bottom: 982, radius: 12
        ))
        let negative = TopBarPositionBox.outline(width: 1512, height: 982, inset: -3, radius: 12)
        #expect(negative == flush)
        let infinite = TopBarPositionBox.outline(width: .infinity, height: .infinity, inset: .infinity)
        #expect(infinite.radius == 0)
        #expect(infinite.centerX == 0)
        #expect(infinite.right == 0)
    }

    @Test func aNegativeOrUnreadableRadiusReadsAsNone() {
        let none = TopBarPositionBox.outline(width: 1512, height: 982, radius: -4)
        #expect(none.radius == 0)
        #expect(none.centerX == 756)
        #expect(none.right == 1510)
        #expect(TopBarPositionBox.outline(width: 1512, height: 982, radius: .nan).radius == 0)
        #expect(TopBarPositionBox.outline(width: 1512, height: 982, radius: .infinity).radius == 0)
    }
}
