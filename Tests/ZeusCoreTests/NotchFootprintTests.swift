import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Notch footprint") struct NotchFootprintTests {
    /// A notched laptop display at the origin: 1512 wide, two 664 pt side areas, a 32 pt inset.
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let hardware = CGSize(width: 184, height: 32)

    private func facts(_ frame: CGRect, inset: CGFloat = 32, left: CGFloat = 664, right: CGFloat = 664) -> NotchDisplayFacts {
        NotchDisplayFacts(frame: frame, safeAreaTop: inset, leftAreaWidth: left, rightAreaWidth: right)
    }

    private func wings(none: Bool, lights: Bool = false, live: Bool = false, extra: CGFloat = 0) -> ClosedWingsFacts {
        ClosedWingsFacts(kindIsNone: none, hasLights: lights, hasLiveActivity: live, extraWidth: extra)
    }

    // MARK: Which footprint a display gets

    @Test func aNotchedDisplayIsTheHardwareNotch() {
        #expect(NotchFootprintRules.hardwareSize(facts(laptop)) == hardware)
        #expect(NotchFootprintRules.resolve(facts(laptop)) == .hardware(hardware))
    }

    @Test func anInsetWithoutSideAreasIsNotANotch() {
        let insetOnly = facts(laptop, left: 0, right: 0)
        #expect(NotchFootprintRules.hardwareSize(insetOnly) == nil)
        #expect(NotchFootprintRules.resolve(insetOnly) == .pill)
    }

    @Test func missingOrHostileFactsGiveThePill() {
        let hostile: [NotchDisplayFacts] = [
            facts(laptop, left: 0),
            facts(laptop, right: 0),
            facts(laptop, left: -5),
            facts(laptop, right: -664),
            facts(laptop, inset: 0),
            facts(laptop, inset: -32),
            facts(laptop, inset: .nan),
            facts(laptop, left: .nan),
            facts(laptop, right: .infinity),
            facts(CGRect(x: 0, y: 0, width: CGFloat.nan, height: 982)),
            facts(CGRect(x: 0, y: 0, width: 0, height: 982)),
            facts(CGRect(x: 0, y: 0, width: -1512, height: 982)),
        ]
        for item in hostile {
            #expect(NotchFootprintRules.hardwareSize(item) == nil)
            #expect(NotchFootprintRules.resolve(item) == .pill)
        }
    }

    @Test func aDisplayWithNoNotchGetsThePillAndAHardwareNotchDoesNot() {
        #expect(NotchFootprintRules.resolve(facts(external, inset: 0, left: 0, right: 0)).isPill)
        #expect(!NotchFootprintRules.resolve(facts(laptop)).isPill)
    }

    @Test func agreesWithTheScreenCornerRuleWhereThereIsRoomForANotch() {
        let table: [(inset: CGFloat, left: CGFloat, right: CGFloat)] = [
            (32, 664, 664), (38, 600, 600), (0, 664, 664), (32, 0, 664), (32, 664, 0), (32, 0, 0),
            (-1, 664, 664), (32, -1, 664), (32, 664, -1), (0, 0, 0), (32, 100, 900),
        ]
        for row in table {
            let expected = ScreenCorners.hasNotch(safeAreaTop: Double(row.inset), leftAreaWidth: Double(row.left),
                                                  rightAreaWidth: Double(row.right))
            let answer = NotchFootprintRules.hardwareSize(facts(laptop, inset: row.inset, left: row.left, right: row.right)) != nil
            #expect(answer == expected)
        }
    }

    @Test func isStricterThanTheScreenCornerRuleOnAnInfiniteWidth() {
        let infinite = facts(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 982))
        #expect(ScreenCorners.hasNotch(safeAreaTop: 32, leftAreaWidth: 664, rightAreaWidth: 664))
        #expect(NotchFootprintRules.hardwareSize(infinite) == nil)
    }

    @Test func isStricterThanTheScreenCornerRuleWhenTheAreasFillTheFrame() {
        let full = facts(laptop, left: 756, right: 756)
        #expect(ScreenCorners.hasNotch(safeAreaTop: 32, leftAreaWidth: 756, rightAreaWidth: 756))
        #expect(NotchFootprintRules.hardwareSize(full) == nil)
        #expect(NotchFootprintRules.hardwareSize(facts(laptop, left: 800, right: 800)) == nil)
    }

    // MARK: Sizes

    @Test func footprintSizes() {
        let notch = NotchFootprint.hardware(hardware)
        #expect(notch.layoutSize == hardware)
        #expect(notch.idleSize == hardware)
        #expect(notch.wingBase == 184)
        #expect(!notch.isPill)

        let pill = NotchFootprint.pill
        #expect(pill.layoutSize == .zero)
        #expect(pill.idleSize == CGSize(width: 96, height: 9))
        #expect(pill.wingBase == 40)
        #expect(pill.isPill)
    }

    // MARK: Hover zone

    @Test func hoverZoneOfTheHardwareNotchAndThePill() {
        let notch = NotchFootprintRules.hoverZone(.hardware(hardware), screenFrame: laptop, topOffset: 0, wings: nil)
        #expect(notch == CGRect(x: 664, y: 951, width: 184, height: 31))
        let pill = NotchFootprintRules.hoverZone(.pill, screenFrame: external, topOffset: 0, wings: nil)
        #expect(pill == CGRect(x: 880, y: 1051, width: 160, height: 29))
    }

    @Test func hoverZoneIsTallerByTheTopOffset() {
        let notch = NotchFootprintRules.hoverZone(.hardware(hardware), screenFrame: laptop, topOffset: 24, wings: nil)
        #expect(notch == CGRect(x: 664, y: 927, width: 184, height: 55))
        let pill = NotchFootprintRules.hoverZone(.pill, screenFrame: external, topOffset: 24, wings: nil)
        #expect(pill == CGRect(x: 880, y: 1027, width: 160, height: 53))
    }

    @Test func hoverZoneWidensByTheWingsAndTheirExtraWidth() {
        let plain = wings(none: false)
        let cue = wings(none: false, extra: 58)
        // Each wing is 62 pt and the ear 8 pt: 140 pt for the pair.
        #expect(NotchFootprintRules.hoverZone(.pill, screenFrame: external, topOffset: 0, wings: plain).width == 300)
        #expect(NotchFootprintRules.hoverZone(.pill, screenFrame: external, topOffset: 0, wings: cue).width == 358)
        #expect(NotchFootprintRules.hoverZone(.hardware(hardware), screenFrame: laptop, topOffset: 0, wings: plain).width == 324)
        #expect(NotchFootprintRules.hoverZone(.hardware(hardware), screenFrame: laptop, topOffset: 0, wings: cue).width == 382)
        let zone = NotchFootprintRules.hoverZone(.pill, screenFrame: external, topOffset: 24, wings: cue)
        #expect(zone.midX == external.midX)
        #expect(zone.height == 53)
    }

    @Test func aLitLightWithNoWingKindWidensTheBodyAndNotTheHoverZone() {
        let light = wings(none: true, lights: true)
        let activity = wings(none: true, live: true)
        #expect(light.showsWings)
        #expect(activity.showsWings)
        for item in [light, activity, wings(none: true)] {
            #expect(NotchFootprintRules.hoverZone(.hardware(hardware), screenFrame: laptop, topOffset: 0, wings: item)
                    == CGRect(x: 664, y: 951, width: 184, height: 31))
            #expect(NotchFootprintRules.hoverZone(.pill, screenFrame: external, topOffset: 0, wings: item)
                    == CGRect(x: 880, y: 1051, width: 160, height: 29))
        }
    }

    @Test func hoverZoneFollowsAScreenAtANegativeOrigin() {
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let pill = NotchFootprintRules.hoverZone(.pill, screenFrame: left, topOffset: 0, wings: nil)
        #expect(pill == CGRect(x: -1040, y: 851, width: 160, height: 29))
        let click = NotchFootprintRules.clickZone(.pill, screenFrame: left, topOffset: 0)
        #expect(click == CGRect(x: -1020, y: 866, width: 120, height: 14))
    }

    // MARK: Click zone

    @Test func clickZoneIsTheOpenRuleWithTheLayoutSize() {
        for offset: CGFloat in [0, 12, 24] {
            #expect(NotchFootprintRules.clickZone(.hardware(hardware), screenFrame: laptop, topOffset: offset)
                    == NotchOpenRules.clickZone(screenFrame: laptop, notchSize: hardware, topOffset: offset))
            #expect(NotchFootprintRules.clickZone(.pill, screenFrame: external, topOffset: offset)
                    == NotchOpenRules.clickZone(screenFrame: external, notchSize: .zero, topOffset: offset))
        }
        #expect(NotchFootprintRules.clickZone(.hardware(hardware), screenFrame: laptop, topOffset: 0)
                == CGRect(x: 664, y: 950, width: 184, height: 32))
        #expect(NotchFootprintRules.clickZone(.pill, screenFrame: external, topOffset: 0)
                == CGRect(x: 900, y: 1066, width: 120, height: 14))
    }

    // MARK: Closed width motion

    /// The closed body width as `NotchView` lays it out: shoulder 0 for the pill and for an idle notch, 8 otherwise.
    private func closedWidth(_ footprint: NotchFootprint, _ item: ClosedWingsFacts) -> CGFloat {
        let shoulder: CGFloat = footprint.isPill ? 0 : (item.kindIsNone ? 0 : 8)
        if item.showsWings {
            return NotchClosedBodyLayout.bodyWidth(notchWidth: footprint.wingBase, shoulder: shoulder, showWings: true,
                                                   extraWidth: item.extraWidth, hasNotch: !footprint.isPill, slimPill: footprint.isPill)
        }
        return footprint.isPill ? footprint.idleSize.width : footprint.idleSize.width + 2 * shoulder
    }

    private var everyWingFacts: [ClosedWingsFacts] {
        var all: [ClosedWingsFacts] = []
        for none in [true, false] {
            for lights in [true, false] {
                for live in [true, false] {
                    for extra: CGFloat in [0, 58] {
                        all.append(wings(none: none, lights: lights, live: live, extra: extra))
                    }
                }
            }
        }
        return all
    }

    @Test func showsWingsIsTheLayoutRulesAnswer() {
        for item in everyWingFacts {
            #expect(item.showsWings == NotchClosedBodyLayout.showWings(
                closedWingKindIsNone: item.kindIsNone, hasLights: item.hasLights, hasLiveActivity: item.hasLiveActivity))
        }
    }

    @Test func differentClosedWidthsNeverShareAMotionKey() {
        for footprint in [NotchFootprint.hardware(hardware), .pill] {
            for first in everyWingFacts {
                for second in everyWingFacts where closedWidth(footprint, first) != closedWidth(footprint, second) {
                    #expect(first.motionKey != second.motionKey)
                }
            }
        }
    }

    @Test func theSameFactsShareAMotionKey() {
        #expect(wings(none: false, lights: true, extra: 58).motionKey == wings(none: false, lights: true, extra: 58).motionKey)
        #expect(wings(none: true).motionKey == wings(none: true, lights: false, live: false, extra: 0).motionKey)
    }
}
