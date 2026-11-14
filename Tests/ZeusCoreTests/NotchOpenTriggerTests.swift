import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Notch open trigger") struct NotchOpenTriggerTests {
    /// A notched laptop display at the origin: 1512 wide, hardware notch 184 by 32.
    private let notched = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let notch = CGSize(width: 184, height: 32)

    @Test func labelsMapToTriggersAndAnythingUnknownIsHover() {
        #expect(NotchOpenTrigger(label: "Hover") == .hover)
        #expect(NotchOpenTrigger(label: "Click") == .click)
        #expect(NotchOpenTrigger(label: "") == .hover)
        #expect(NotchOpenTrigger(label: "click") == .hover)
        #expect(NotchOpenTrigger(label: "Double click") == .hover)
    }

    @Test func hoverOpensOnlyForTheHoverTrigger() {
        #expect(NotchOpenRules.opensOnHover(.hover))
        #expect(!NotchOpenRules.opensOnHover(.click))
    }

    @Test func notchedScreenUsesTheHardwareNotchRectangle() {
        let zone = NotchOpenRules.clickZone(screenFrame: notched, notchSize: notch, topOffset: 0)
        #expect(zone == CGRect(x: 664, y: 950, width: 184, height: 32))
    }

    @Test func screenWithoutANotchUsesThePillGrownTwelveSidewaysAndFourteenTall() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let zone = NotchOpenRules.clickZone(screenFrame: screen, notchSize: .zero, topOffset: 0)
        // The 96 pt pill, 12 pt more on each side, 14 pt tall, hanging from the top edge.
        #expect(zone == CGRect(x: 912 - 12, y: 1080 - 14, width: 96 + 24, height: 14))
    }

    @Test func negativeOriginAndTopOffsetMoveThePillZoneWithTheScreen() {
        // A second display to the left and below the main one, with the bar lowered 10 pt.
        let screen = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let zone = NotchOpenRules.clickZone(screenFrame: screen, notchSize: .zero, topOffset: 10)
        #expect(zone == CGRect(x: -960 - 60, y: 0 - 10 - 14, width: 120, height: 14))
        #expect(zone.midX == screen.midX)
    }

    @Test func notchedScreenWithANegativeOriginKeepsTheNotchAtTheTop() {
        let screen = CGRect(x: -1512, y: 200, width: 1512, height: 982)
        let zone = NotchOpenRules.clickZone(screenFrame: screen, notchSize: notch, topOffset: 0)
        #expect(zone == CGRect(x: -756 - 92, y: 1182 - 32, width: 184, height: 32))
    }

    @Test func loweredBarOnANotchedScreenExtendsTheZoneDownToTheVisibleIsland() {
        let screen = CGRect(x: -1512, y: 200, width: 1512, height: 982)
        let zone = NotchOpenRules.clickZone(screenFrame: screen, notchSize: notch, topOffset: 12)
        // Still only notch-wide, so menu bar items stay clear; 12 pt taller, so the lowered island is covered.
        #expect(zone == CGRect(x: -756 - 92, y: 1182 - 32 - 12, width: 184, height: 32 + 12))
        let island = CGPoint(x: -756, y: 1182 - 32 - 6)
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: island, zone: zone))
    }

    @Test func aNegativeTopOffsetNeverShrinksTheNotchedZone() {
        let zone = NotchOpenRules.clickZone(screenFrame: notched, notchSize: notch, topOffset: -8)
        #expect(zone == CGRect(x: 664, y: 950, width: 184, height: 32))
    }

    @Test func aNotchWithNoHeightOrNoWidthFallsBackToThePillZone() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let pill = NotchOpenRules.clickZone(screenFrame: screen, notchSize: .zero, topOffset: 0)
        #expect(NotchOpenRules.clickZone(screenFrame: screen, notchSize: CGSize(width: 184, height: 0), topOffset: 0) == pill)
        #expect(NotchOpenRules.clickZone(screenFrame: screen, notchSize: CGSize(width: 0, height: 32), topOffset: 0) == pill)
    }

    @Test func clickInsideTheZoneOpensWhenClosedAndTheTriggerIsClick() {
        let zone = NotchOpenRules.clickZone(screenFrame: notched, notchSize: notch, topOffset: 0)
        let inside = CGPoint(x: 756, y: 970)
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: inside, zone: zone))
        // The top row of the screen counts, like the hover zone.
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: 756, y: 982), zone: zone))
    }

    @Test func clickOutsideTheZoneDoesNotOpen() {
        let zone = NotchOpenRules.clickZone(screenFrame: notched, notchSize: notch, topOffset: 0)
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: 600, y: 970), zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: 900, y: 970), zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: 756, y: 900), zone: zone))
        // The bottom edge is outside, as it is for the hover zone.
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: 756, y: 950), zone: zone))
    }

    @Test func theLeftAndRightEdgesCountAndJustOutsideDoesNot() {
        let zone = NotchOpenRules.clickZone(screenFrame: notched, notchSize: notch, topOffset: 0)
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: zone.minX, y: 970), zone: zone))
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: zone.maxX, y: 970), zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: zone.minX - 0.5, y: 970), zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: zone.maxX + 0.5, y: 970), zone: zone))
    }

    @Test func clickOnThePillZoneOfADisplayWithoutANotch() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let zone = NotchOpenRules.clickZone(screenFrame: screen, notchSize: .zero, topOffset: 0)
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: 960, y: 1070), zone: zone))
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: zone.minX, y: 1070), zone: zone))
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: zone.maxX, y: 1070), zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: zone.minX - 1, y: 1070), zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: zone.maxX + 1, y: 1070), zone: zone))
        // Below the 14 pt zone, where menu bar items live.
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: 960, y: 1060), zone: zone))
    }

    @Test func clickOnThePillZoneOfALoweredBarOnANegativeOriginDisplay() {
        let screen = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let zone = NotchOpenRules.clickZone(screenFrame: screen, notchSize: .zero, topOffset: 10)
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: -960, y: -15), zone: zone))
        // The 10 pt gap above the lowered pill is not the pill.
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: -960, y: -5), zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: -960, y: -30), zone: zone))
    }

    @Test func aClickOpensFromThePeekBecauseOnlyThePanelCountsAsOpen() {
        let zone = NotchOpenRules.clickZone(screenFrame: notched, notchSize: notch, topOffset: 0)
        let inside = CGPoint(x: 756, y: 970)
        // The controller passes `presentation == .panel`: a peek is not the panel.
        let peekIsPanel = false
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: peekIsPanel, point: inside, zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: true, point: inside, zone: zone))
    }

    @Test func noOpenWhenTheNotchIsAlreadyOpen() {
        let zone = NotchOpenRules.clickZone(screenFrame: notched, notchSize: notch, topOffset: 0)
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: true, point: CGPoint(x: 756, y: 970), zone: zone))
    }

    @Test func noOpenForHoverEvenInsideTheZone() {
        let zone = NotchOpenRules.clickZone(screenFrame: notched, notchSize: notch, topOffset: 0)
        #expect(!NotchOpenRules.opensOnClick(trigger: .hover, panelIsOpen: false, point: CGPoint(x: 756, y: 970), zone: zone))
    }
}
