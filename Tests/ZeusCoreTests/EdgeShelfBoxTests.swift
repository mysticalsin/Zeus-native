import Foundation
import Testing
@testable import ZeusCore

/// Edge-shelf frames as plain numbers. A tucked card keeps its full size and slides so only the tab
/// stays on screen. The top offset is the gap from the visible top down to the card's top.
@Suite("Edge shelf box")
struct EdgeShelfBoxTests {
    private func frame(_ edge: EdgeShelfBox.Edge, top: Double = 0, expanded: Bool,
                       minX: Double = 0, maxX: Double = 1440, maxY: Double = 875, height: Double = 875,
                       width: Double = 260, cardHeight: Double = 220) -> EdgeShelfBox.Rect {
        EdgeShelfBox.frame(
            edge: edge, top: top, expanded: expanded,
            visibleMinX: minX, visibleMaxX: maxX, visibleMaxY: maxY, visibleHeight: height,
            width: width, height: cardHeight)
    }

    @Test func theTabIs22AndTheCardIs260By220() {
        #expect(EdgeShelfBox.tabWidth == 22)
        #expect(EdgeShelfBox.cardWidth == 260)
        #expect(EdgeShelfBox.cardHeight == 220)
        #expect(EdgeShelfBox.snapDistance == 24)
        let standard = EdgeShelfBox.frame(
            edge: .right, top: 0, expanded: true,
            visibleMinX: 0, visibleMaxX: 1440, visibleMaxY: 875, visibleHeight: 875)
        #expect(standard.width == 260)
        #expect(standard.height == 220)
        #expect(standard.x == 1440 - 260)
    }

    @Test func aTuckedRightCardShowsOnlyTheTab() {
        let tucked = frame(.right, top: 100, expanded: false)
        #expect(tucked.x == 1440 - 22)
        #expect(tucked.y + tucked.height == 775)
        #expect(tucked.width == 260)
        #expect(tucked.height == 220)
    }

    @Test func anExpandedRightCardSitsFlushWithTheScreen() {
        let open = frame(.right, top: 100, expanded: true)
        #expect(open.x + open.width == 1440)
        #expect(open.y == 875 - 100 - 220)
    }

    @Test func aLeftCardTucksOffTheLeftAndOpensAtTheEdge() {
        let tucked = frame(.left, expanded: false)
        #expect(tucked.x + tucked.width == 22)
        #expect(tucked.x == 0 - 260 + 22)
        let open = frame(.left, expanded: true)
        #expect(open.x == 0)
        #expect(open.width == 260)
    }

    @Test func theTopOffsetClampsInsideTheVisibleFrame() {
        let dropped = frame(.left, top: 5000, expanded: true)
        #expect(dropped.y == 0)
        #expect(dropped.height == 220)
        let lifted = frame(.right, top: -40, expanded: true)
        #expect(lifted.y + lifted.height == 875)
        #expect(lifted.x == 1440 - 260)
    }

    @Test func aCardTallerThanTheScreenHangsFromTheTop() {
        let card = frame(.left, top: 30, expanded: true, maxX: 400, maxY: 100, height: 100, cardHeight: 220)
        #expect(card.y + card.height == 100)
        #expect(card.y == 100 - 220)
        #expect(card.height == 220)
    }

    @Test func anOffsetScreenUsesItsOwnEdges() {
        let tucked = frame(.right, top: 40, expanded: false, minX: 80, maxX: 1520, maxY: 1000, height: 900)
        #expect(tucked.x == 1520 - 22)
        #expect(tucked.y == 1000 - 40 - 220)
        let open = frame(.left, top: 40, expanded: true, minX: 80, maxX: 1520, maxY: 1000, height: 900)
        #expect(open.x == 80)
        #expect(open.y == 1000 - 40 - 220)
    }

    @Test func aCustomSizeKeepsThatSizeWhenTucked() {
        let card = frame(.right, expanded: false, maxX: 500, maxY: 400, height: 400, width: 100, cardHeight: 50)
        #expect(card.x == 500 - 22)
        #expect(card.y == 400 - 50)
        #expect(card.width == 100)
        #expect(card.height == 50)
    }

    @Test func aCardNearEitherEdgeSnapsAndTheMiddleStaysPut() {
        #expect(EdgeShelfBox.snapEdge(frameMinX: 10, frameMaxX: 270, visibleMinX: 0, visibleMaxX: 1440) == .left)
        #expect(EdgeShelfBox.snapEdge(frameMinX: 24, frameMaxX: 284, visibleMinX: 0, visibleMaxX: 1440) == .left)
        #expect(EdgeShelfBox.snapEdge(frameMinX: 25, frameMaxX: 285, visibleMinX: 0, visibleMaxX: 1440) == nil)
        #expect(EdgeShelfBox.snapEdge(frameMinX: 1170, frameMaxX: 1430, visibleMinX: 0, visibleMaxX: 1440) == .right)
        #expect(EdgeShelfBox.snapEdge(frameMinX: 1156, frameMaxX: 1416, visibleMinX: 0, visibleMaxX: 1440) == .right)
        #expect(EdgeShelfBox.snapEdge(frameMinX: 1155, frameMaxX: 1415, visibleMinX: 0, visibleMaxX: 1440) == nil)
        #expect(EdgeShelfBox.snapEdge(frameMinX: 600, frameMaxX: 860, visibleMinX: 0, visibleMaxX: 1440) == nil)
        #expect(EdgeShelfBox.snapEdge(frameMinX: 1, frameMaxX: 261, visibleMinX: 0, visibleMaxX: 1440, snap: 0) == nil)
        #expect(EdgeShelfBox.snapEdge(frameMinX: 0, frameMaxX: 260, visibleMinX: 0, visibleMaxX: 1440, snap: 0) == .left)
    }

    @Test func bothEdgesInRangePreferTheLeft() {
        #expect(EdgeShelfBox.snapEdge(frameMinX: 10, frameMaxX: 270, visibleMinX: 0, visibleMaxX: 280) == .left)
    }

    @Test func theStoredTopIsTheGapUnderTheVisibleTop() {
        #expect(EdgeShelfBox.top(frameMaxY: 675, visibleMaxY: 875) == 200)
        #expect(EdgeShelfBox.top(frameMaxY: 875, visibleMaxY: 875) == 0)
        #expect(EdgeShelfBox.top(frameMaxY: 900, visibleMaxY: 875) == 0)
    }
}
