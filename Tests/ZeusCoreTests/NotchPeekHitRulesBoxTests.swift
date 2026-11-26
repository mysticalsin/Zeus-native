import Foundation
import Testing
@testable import ZeusCore

@Suite struct NotchPeekHitRulesBoxTests {
    private let screenMinX = 0.0
    private let screenWidth = 1512.0
    private let screenMaxY = 982.0
    private let cardWidth = 440.0
    private let cardHeight = 160.0

    private func card(topOffset: Double = 0, width: Double? = nil, height: Double? = nil,
                      minX: Double? = nil, widthOfScreen: Double? = nil, maxY: Double? = nil) -> NotchPeekHitRulesBox.Rect {
        NotchPeekHitRulesBox.cardRect(
            width: width ?? cardWidth,
            height: height ?? cardHeight,
            screenMinX: minX ?? screenMinX,
            screenWidth: widthOfScreen ?? screenWidth,
            screenMaxY: maxY ?? screenMaxY,
            topOffset: topOffset)
    }

    private func takes(_ x: Double, fromTop: Double, topOffset: Double = 0,
                       width: Double? = nil, height: Double? = nil) -> Bool {
        NotchPeekHitRulesBox.takesMouse(
            x: x, y: screenMaxY - fromTop,
            width: width ?? cardWidth, height: height ?? cardHeight,
            screenMinX: screenMinX, screenWidth: screenWidth, screenMaxY: screenMaxY,
            topOffset: topOffset)
    }

    @Test func cardIsCentredAndHangsFromTheTop() {
        let rect = card()
        #expect(rect.x == 536)
        #expect(rect.y == 822)
        #expect(rect.width == 440)
        #expect(rect.height == 160)
        #expect(NotchPeekHitRulesBox.slack == 6)
    }

    @Test func aNegativeTopOffsetIsTreatedAsZero() {
        let dropped = card(topOffset: -4)
        let flush = card(topOffset: 0)
        #expect(dropped == flush)
        #expect(dropped.y == 822)
    }

    @Test func pointerOverTheCardTakesTheMouse() {
        #expect(takes(756, fromTop: 20))
        #expect(takes(956, fromTop: 150))
        #expect(takes(541, fromTop: 80))
    }

    @Test func pointerFarBelowTheCardIsClickThrough() {
        #expect(takes(756, fromTop: 20))
        #expect(!takes(756, fromTop: 300))
        #expect(!takes(756, fromTop: 460))
    }

    @Test func pointerBesideTheCardIsClickThrough() {
        #expect(takes(756, fromTop: 20))
        #expect(!takes(2, fromTop: 20))
        #expect(!takes(1510, fromTop: 100))
        #expect(!takes(1056, fromTop: 60))
    }

    @Test func aFewPointsOfSlackSurroundTheCard() {
        #expect(takes(980, fromTop: 50))
        #expect(takes(756, fromTop: 164))
        #expect(!takes(996, fromTop: 50))
        #expect(!takes(756, fromTop: 180))
    }

    @Test func theCardHangsLowerWhenTheTopOffsetGrows() {
        #expect(card(topOffset: 20).y == 802)
        #expect(takes(756, fromTop: 180, topOffset: 20))
        #expect(!takes(756, fromTop: 200, topOffset: 20))
    }

    @Test func aTallerCardReachesFurtherDown() {
        #expect(takes(756, fromTop: 320, width: 520, height: 330))
        #expect(!takes(756, fromTop: 320))
        #expect(card(width: 520, height: 330).x == 496)
        #expect(card(width: 520, height: 330).y == 652)
    }

    @Test func theFarEdgeOfTheHitRectDoesNotTakeTheMouse() {
        #expect(takes(981, fromTop: 82))
        #expect(!takes(982, fromTop: 82))
        #expect(takes(530, fromTop: 166))
        #expect(!takes(529, fromTop: 166))
        #expect(takes(756, fromTop: 166))
        #expect(!takes(756, fromTop: 167))
        let above = NotchPeekHitRulesBox.takesMouse(
            x: 756, y: 987, width: cardWidth, height: cardHeight,
            screenMinX: screenMinX, screenWidth: screenWidth, screenMaxY: screenMaxY, topOffset: 0)
        let onMax = NotchPeekHitRulesBox.takesMouse(
            x: 756, y: 988, width: cardWidth, height: cardHeight,
            screenMinX: screenMinX, screenWidth: screenWidth, screenMaxY: screenMaxY, topOffset: 0)
        #expect(above)
        #expect(!onMax)
    }

    @Test func aScreenThatDoesNotStartAtTheOriginStillCentresTheCard() {
        let rect = card(width: 400, height: 200, minX: -1920, widthOfScreen: 1920, maxY: 1080)
        #expect(rect.x == -1160)
        #expect(rect.y == 880)
        #expect(rect.width == 400)
        #expect(rect.height == 200)
        let hit = NotchPeekHitRulesBox.takesMouse(
            x: -960, y: 1070, width: 400, height: 200,
            screenMinX: -1920, screenWidth: 1920, screenMaxY: 1080, topOffset: 0)
        #expect(hit)
    }
}
