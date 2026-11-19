import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

/// The notch window is 1800 x 470 at the top of the screen. While a peek (approval, completion, trouble, recap)
/// is up it must take the mouse only over the visible card, so the rest of that strip stays click-through.
@Suite("Peek click-through") struct NotchPeekHitRulesTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let card = CGSize(width: 440, height: 160)

    private func takes(_ x: CGFloat, fromTop: CGFloat, topOffset: CGFloat = 0, size: CGSize? = nil) -> Bool {
        NotchPeekHitRules.takesMouse(CGPoint(x: x, y: screen.maxY - fromTop), size: size ?? card, screenFrame: screen, topOffset: topOffset)
    }

    @Test func pointerOverThePeekCardTakesTheMouse() {
        #expect(takes(screen.midX, fromTop: 20))
        #expect(takes(screen.midX + 200, fromTop: 150))
        #expect(takes(screen.midX - 215, fromTop: 80))
    }

    @Test func pointerFarBelowTheCardIsClickThrough() {
        #expect(!takes(screen.midX, fromTop: 300))
        #expect(!takes(screen.midX, fromTop: 460))
    }

    @Test func pointerBesideTheCardIsClickThrough() {
        #expect(!takes(screen.minX + 2, fromTop: 20))
        #expect(!takes(screen.maxX - 2, fromTop: 100))
        #expect(!takes(screen.midX + 300, fromTop: 60))
    }

    @Test func aFewPointsOfSlackSurroundTheCard() {
        #expect(takes(screen.midX + card.width / 2 + 4, fromTop: 50))
        #expect(takes(screen.midX, fromTop: card.height + 4))
        #expect(!takes(screen.midX + card.width / 2 + 20, fromTop: 50))
        #expect(!takes(screen.midX, fromTop: card.height + 20))
    }

    @Test func theCardHangsFromTheTopOffset() {
        #expect(takes(screen.midX, fromTop: 20 + 160, topOffset: 20))
        #expect(!takes(screen.midX, fromTop: 20 + 160 + 20, topOffset: 20))
    }

    @Test func aTallerApprovalCardReachesFurther() {
        let tall = CGSize(width: 520, height: 330)
        #expect(takes(screen.midX, fromTop: 320, size: tall))
        #expect(!takes(screen.midX, fromTop: 320))
    }

    @Test func theClosedAndPanelRulesAreUntouched() {
        let panel = GlanceTopBar.panelSize(home: true, extra: 0)
        #expect(GlanceTopBar.openShapeContains(CGPoint(x: screen.midX, y: screen.maxY - 10), screen: screen, size: panel))
        #expect(!GlanceTopBar.openShapeContains(CGPoint(x: screen.maxX - 2, y: screen.maxY - 10), screen: screen, size: panel))
    }
}
