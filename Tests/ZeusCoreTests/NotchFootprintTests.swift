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

    // MARK: Drawn shape

    private let drawn = NotchFootprint.drawn(DrawnNotchShape(width: 185, height: 32, offset: 0))
    private let smallDrawn = NotchFootprint.drawn(DrawnNotchShape(width: 140, height: 30, offset: 0))

    /// Every wings state the closed body can be in, with and without a top bar.
    private var everyWingsState: [ClosedWingsFacts?] {
        [nil, wings(none: true), wings(none: true, lights: true), wings(none: true, live: true),
         wings(none: false), wings(none: false, extra: 58), wings(none: false, lights: true, live: true, extra: 58)]
    }

    @Test func aDrawnFootprintIsSizedLikeAHardwareNotchOfThatSize() {
        let size = CGSize(width: 185, height: 32)
        #expect(drawn.layoutSize == size)
        #expect(drawn.idleSize == size)
        #expect(drawn.wingBase == 185)
        #expect(!drawn.isPill)
        #expect(smallDrawn.layoutSize == CGSize(width: 140, height: 30))
        #expect(smallDrawn.wingBase == 140)
    }

    @Test func hardwareBeatsADrawnStyle() {
        let shape = DrawnNotchLimits.defaultShape
        #expect(NotchFootprintRules.resolve(facts(laptop), style: .drawn, shape: shape) == .hardware(hardware))
        #expect(NotchFootprintRules.resolve(facts(laptop), style: .pill, shape: shape) == .hardware(hardware))
    }

    @Test func theDrawnStyleGivesTheFittedShapeOnADisplayWithoutANotch() {
        let none = facts(external, inset: 0, left: 0, right: 0)
        let shape = DrawnNotchShape(width: 187, height: 32, offset: 7)
        #expect(NotchFootprintRules.resolve(none, style: .drawn, shape: shape)
                == .drawn(DrawnNotchShape(width: 185, height: 32, offset: 5)))
        let narrow = facts(CGRect(x: 0, y: 0, width: 1024, height: 768), inset: 0, left: 0, right: 0)
        #expect(NotchFootprintRules.resolve(narrow, style: .drawn, shape: DrawnNotchShape(width: 280, height: 32, offset: 400))
                == .drawn(DrawnNotchShape(width: 255, height: 32, offset: 40)))
    }

    @Test func thePillStyleAndAFailedFitGiveThePill() {
        let shape = DrawnNotchLimits.defaultShape
        let none = facts(external, inset: 0, left: 0, right: 0)
        #expect(NotchFootprintRules.resolve(none, style: .pill, shape: shape) == .pill)
        let tooNarrow = facts(CGRect(x: 0, y: 0, width: 500, height: 400), inset: 0, left: 0, right: 0)
        #expect(NotchFootprintRules.resolve(tooNarrow, style: .drawn, shape: shape) == .pill)
        for width in [CGFloat.nan, .infinity, 0, -1920] {
            let hostile = facts(CGRect(x: 0, y: 0, width: width, height: 1080), inset: 0, left: 0, right: 0)
            #expect(NotchFootprintRules.resolve(hostile, style: .drawn, shape: shape) == .pill)
        }
    }

    @Test func theClosedBodyGrowsOnTheFullShowsWingsAnswer() {
        // Idle: the notch's own width. A lit light with no wing kind grows the wings and keeps the shoulders at 0.
        #expect(NotchFootprintRules.closedSize(drawn, wings: nil) == CGSize(width: 185, height: 32))
        #expect(NotchFootprintRules.closedSize(drawn, wings: wings(none: true)) == CGSize(width: 185, height: 32))
        #expect(NotchFootprintRules.closedSize(drawn, wings: wings(none: true, lights: true)) == CGSize(width: 309, height: 32))
        #expect(NotchFootprintRules.closedSize(drawn, wings: wings(none: true, live: true)) == CGSize(width: 309, height: 32))
        // A wing kind brings the 8 pt shoulders: 185 + 16 + 124.
        #expect(NotchFootprintRules.closedSize(drawn, wings: wings(none: false)) == CGSize(width: 325, height: 32))
        #expect(NotchFootprintRules.closedSize(drawn, wings: wings(none: false, extra: 58)) == CGSize(width: 383, height: 32))
        #expect(NotchFootprintRules.closedSize(smallDrawn, wings: wings(none: true)) == CGSize(width: 140, height: 30))
    }

    @Test func theClosedSizeOfTheOtherFootprintsIsTodaysLayout() {
        #expect(NotchFootprintRules.closedSize(.pill, wings: nil) == CGSize(width: 96, height: 9))
        #expect(NotchFootprintRules.closedSize(.pill, wings: wings(none: true, lights: true)) == CGSize(width: 164, height: 30))
        #expect(NotchFootprintRules.closedSize(.hardware(hardware), wings: nil) == CGSize(width: 184, height: 32))
        #expect(NotchFootprintRules.closedSize(.hardware(hardware), wings: wings(none: false)) == CGSize(width: 324, height: 32))
        for footprint in [NotchFootprint.hardware(hardware), .pill] {
            for item in everyWingFacts {
                #expect(NotchFootprintRules.closedSize(footprint, wings: item).width == closedWidth(footprint, item))
            }
        }
    }

    @Test func theBodyRectangleIsCentredAndHangsFromTheTopOffset() {
        let body = NotchFootprintRules.bodyRect(drawn, screenFrame: external, topOffset: 0, wings: nil)
        #expect(body == CGRect(x: 867.5, y: 1048, width: 185, height: 32))
        let wide = NotchFootprintRules.bodyRect(drawn, screenFrame: external, topOffset: 0, wings: wings(none: true, lights: true))
        #expect(wide == CGRect(x: 805.5, y: 1048, width: 309, height: 32))
        let lowered = NotchFootprintRules.bodyRect(drawn, screenFrame: external, topOffset: 24, wings: nil)
        #expect(lowered == CGRect(x: 867.5, y: 1024, width: 185, height: 32))
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        #expect(NotchFootprintRules.bodyRect(drawn, screenFrame: left, topOffset: 0, wings: nil)
                == CGRect(x: -1052.5, y: 848, width: 185, height: 32))
    }

    @Test func forADrawnShapeTheBodyHoverAndClickRectanglesAreOne() {
        for item in everyWingsState {
            for offset: CGFloat in [0, 24] {
                for footprint in [drawn, smallDrawn] {
                    let body = NotchFootprintRules.bodyRect(footprint, screenFrame: external, topOffset: offset, wings: item)
                    #expect(NotchFootprintRules.hoverZone(footprint, screenFrame: external, topOffset: offset, wings: item) == body)
                    #expect(NotchFootprintRules.clickZone(footprint, screenFrame: external, topOffset: offset, wings: item) == body)
                }
            }
        }
    }

    @Test func aLoweredDrawnShapeClaimsNothingAboveItself() {
        let zone = NotchFootprintRules.hoverZone(drawn, screenFrame: external, topOffset: 24, wings: nil)
        #expect(zone.maxY == external.maxY - 24)
        let click = NotchFootprintRules.clickZone(drawn, screenFrame: external, topOffset: 24, wings: nil)
        #expect(click.maxY == external.maxY - 24)
    }

    @Test func theHardwareNotchAndThePillKeepTheirZones() {
        let item = wings(none: false, extra: 58)
        for offset: CGFloat in [0, 24] {
            #expect(NotchFootprintRules.hoverZone(.hardware(hardware), screenFrame: laptop, topOffset: offset, wings: item)
                    == NotchFootprintRules.hoverZone(.hardware(hardware), screenFrame: laptop, topOffset: offset, wings: item))
            #expect(NotchFootprintRules.clickZone(.hardware(hardware), screenFrame: laptop, topOffset: offset, wings: item)
                    == NotchOpenRules.clickZone(screenFrame: laptop, notchSize: hardware, topOffset: offset))
            #expect(NotchFootprintRules.clickZone(.pill, screenFrame: external, topOffset: offset, wings: item)
                    == NotchOpenRules.clickZone(screenFrame: external, notchSize: .zero, topOffset: offset))
        }
        #expect(NotchFootprintRules.hoverZone(.pill, screenFrame: external, topOffset: 0, wings: nil)
                == CGRect(x: 880, y: 1051, width: 160, height: 29))
    }

    // MARK: Taking the mouse

    @Test func theMouseIsTakenInsideTheClosedDrawnBodyOnly() {
        // The body is x 867.5 to 1052.5 and y 1048 to 1080 on the 1920 by 1080 display.
        func takes(_ x: CGFloat, _ y: CGFloat, closed: Bool = true, _ footprint: NotchFootprint? = nil) -> Bool {
            NotchFootprintRules.takesMouse(footprint ?? drawn, closed: closed, point: CGPoint(x: x, y: y),
                                           screenFrame: external, topOffset: 0, wings: nil)
        }
        #expect(takes(960, 1060))
        #expect(takes(867.5, 1060))
        #expect(takes(1052.5, 1060))
        #expect(!takes(867.4, 1060))
        #expect(!takes(1052.6, 1060))
        // The top edge counts and the bottom edge does not.
        #expect(takes(960, 1080))
        #expect(!takes(960, 1080.1))
        #expect(takes(960, 1048.1))
        #expect(!takes(960, 1048))
        #expect(!takes(960, 1000))
    }

    @Test func theMouseIsNeverTakenForAnyOtherStateOrFootprint() {
        let inside = CGPoint(x: 960, y: 1060)
        #expect(!NotchFootprintRules.takesMouse(drawn, closed: false, point: inside, screenFrame: external, topOffset: 0, wings: nil))
        #expect(!NotchFootprintRules.takesMouse(.pill, closed: true, point: inside, screenFrame: external, topOffset: 0, wings: nil))
        let inLaptop = CGPoint(x: 756, y: 975)
        #expect(!NotchFootprintRules.takesMouse(.hardware(hardware), closed: true, point: inLaptop, screenFrame: laptop,
                                                topOffset: 0, wings: nil))
    }

    @Test func aLoweredDrawnBodyDoesNotTakeTheMouseAboveItself() {
        #expect(!NotchFootprintRules.takesMouse(drawn, closed: true, point: CGPoint(x: 960, y: 1070), screenFrame: external,
                                                topOffset: 24, wings: nil))
        #expect(NotchFootprintRules.takesMouse(drawn, closed: true, point: CGPoint(x: 960, y: 1040), screenFrame: external,
                                               topOffset: 24, wings: nil))
    }

    @Test func theTakenAreaFollowsTheWingsWidth() {
        let light = wings(none: true, lights: true)
        // 309 wide: x 805.5 to 1114.5.
        #expect(NotchFootprintRules.takesMouse(drawn, closed: true, point: CGPoint(x: 810, y: 1060), screenFrame: external,
                                               topOffset: 0, wings: light))
        #expect(!NotchFootprintRules.takesMouse(drawn, closed: true, point: CGPoint(x: 810, y: 1060), screenFrame: external,
                                                topOffset: 0, wings: nil))
    }

    // MARK: Motion key with drawn shapes

    @Test func differentDrawnClosedWidthsNeverShareAMotionKey() {
        for footprint in [drawn, smallDrawn] {
            for first in everyWingFacts {
                for second in everyWingFacts
                    where NotchFootprintRules.closedSize(footprint, wings: first).width
                        != NotchFootprintRules.closedSize(footprint, wings: second).width {
                    #expect(first.motionKey != second.motionKey)
                }
            }
        }
    }

    @Test func theMotionKeyDoesNotDependOnTheFootprint() {
        for item in everyWingFacts {
            // The key is a property of the wing facts alone: one drawn shape resized, the pill and the notch share it.
            let key = item.motionKey
            #expect(key == wings(none: item.kindIsNone, lights: item.hasLights, live: item.hasLiveActivity,
                                 extra: item.extraWidth).motionKey)
        }
        #expect(NotchFootprintRules.closedSize(drawn, wings: wings(none: false)).width
                != NotchFootprintRules.closedSize(smallDrawn, wings: wings(none: false)).width)
    }

    // MARK: Words

    @Test func noShapeNameCarriesADash() {
        for footprint in [drawn, smallDrawn, NotchFootprint.pill, .hardware(hardware)] {
            let text = String(describing: footprint)
            #expect(!text.contains("\u{2014}"))
            #expect(!text.contains("\u{2013}"))
        }
    }
}
