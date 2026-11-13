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
        let zone = NotchOpenRules.clickZone(screenFrame: screen, notchSize: notch, topOffset: 12)
        // The hardware notch does not move when the bar is lowered.
        #expect(zone == CGRect(x: -756 - 92, y: 1182 - 32, width: 184, height: 32))
    }

    @Test func clickInsideTheZoneOpensWhenClosedAndTheTriggerIsClick() {
        let zone = NotchOpenRules.clickZone(screenFrame: notched, notchSize: notch, topOffset: 0)
        let inside = CGPoint(x: 756, y: 970)
        #expect(NotchOpenRules.opensOnClick(trigger: .click, isClosed: true, point: inside, zone: zone))
        // The top row of the screen counts, like the hover zone.
        #expect(NotchOpenRules.opensOnClick(trigger: .click, isClosed: true, point: CGPoint(x: 756, y: 982), zone: zone))
    }

    @Test func clickOutsideTheZoneDoesNotOpen() {
        let zone = NotchOpenRules.clickZone(screenFrame: notched, notchSize: notch, topOffset: 0)
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, isClosed: true, point: CGPoint(x: 600, y: 970), zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, isClosed: true, point: CGPoint(x: 900, y: 970), zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, isClosed: true, point: CGPoint(x: 756, y: 900), zone: zone))
        // The bottom edge is outside, as it is for the hover zone.
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, isClosed: true, point: CGPoint(x: 756, y: 950), zone: zone))
    }

    @Test func noOpenWhenTheNotchIsAlreadyOpen() {
        let zone = NotchOpenRules.clickZone(screenFrame: notched, notchSize: notch, topOffset: 0)
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, isClosed: false, point: CGPoint(x: 756, y: 970), zone: zone))
    }

    @Test func noOpenForHoverEvenInsideTheZone() {
        let zone = NotchOpenRules.clickZone(screenFrame: notched, notchSize: notch, topOffset: 0)
        #expect(!NotchOpenRules.opensOnClick(trigger: .hover, isClosed: true, point: CGPoint(x: 756, y: 970), zone: zone))
    }
}
