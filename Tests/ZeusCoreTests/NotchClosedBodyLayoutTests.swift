import CoreGraphics
import Testing
import ZeusCore

@Suite struct NotchClosedBodyLayoutTests {
    @Test func hudCueExpandsClosedBodyWidth() {
        let narrow = NotchClosedBodyLayout.bodyWidth(
            notchWidth: 185, shoulder: 0, showWings: false, extraWidth: 0, hasNotch: true, slimPill: false)
        let wide = NotchClosedBodyLayout.bodyWidth(
            notchWidth: 185, shoulder: 0, showWings: true, extraWidth: 58, hasNotch: true, slimPill: false)
        #expect(narrow == 185)
        #expect(wide > narrow)
        #expect(wide - narrow > 100)
    }

    @Test func wingsSpringTargetsUnder120ms() {
        #expect(NotchClosedBodyLayout.wingsSpringResponse <= 0.12)
    }

    @Test func showWingsWhenHudLightsAppear() {
        #expect(NotchClosedBodyLayout.showWings(closedWingKindIsNone: true, hasLights: true, hasLiveActivity: false))
        #expect(!NotchClosedBodyLayout.showWings(closedWingKindIsNone: true, hasLights: false, hasLiveActivity: false))
    }

    /// Every extra width `ClosedWings.extraWidth(for:)` can return, plus the idle mascot's -36 and no extra.
    private static let everyExtra: [CGFloat] = [-36, 0, 14, 30, 58, 60, 70, 110, 150, 180, 230, 300]
    private static let notchWidths: [CGFloat] = [160, 185, 200, 220, 250]

    @Test func theNotchGapIsExactlyTheNotchForEveryNotchAndExtra() {
        for notch in Self.notchWidths {
            for shoulder: CGFloat in [0, 8] {
                for extra in Self.everyExtra {
                    let g = NotchClosedBodyLayout.closedWingGeometry(notchWidth: notch, shoulder: shoulder, extra: extra)
                    #expect(g.notchGap == -notch / 2 ... notch / 2)
                }
            }
        }
    }

    @Test func wingsAreSymmetricAndNeverOverlapTheGap() {
        for notch in Self.notchWidths {
            for extra in Self.everyExtra {
                let g = NotchClosedBodyLayout.closedWingGeometry(notchWidth: notch, shoulder: 8, extra: extra)
                #expect(g.leftWing.lowerBound == -g.rightWing.upperBound)
                #expect(g.leftWing.upperBound == -g.rightWing.lowerBound)
                #expect(g.leftWing.upperBound <= g.notchGap.lowerBound)
                #expect(g.rightWing.lowerBound >= g.notchGap.upperBound)
                #expect(g.rightWing.upperBound - g.rightWing.lowerBound == NotchClosedBodyLayout.wingWidth - 14 + extra)
            }
        }
    }

    @Test func theWingsFillTheContentBoxInsideTheBodyPadding() {
        for notch in Self.notchWidths {
            for extra in Self.everyExtra {
                let g = NotchClosedBodyLayout.closedWingGeometry(notchWidth: notch, shoulder: 8, extra: extra)
                #expect(g.rightWing.upperBound == g.bodyWidth / 2 - 8 - 14)
                #expect(g.leftWing.lowerBound == -g.bodyWidth / 2 + 8 + 14)
            }
        }
    }

    @Test func bodyWidthGrowsBothWingsByTheExtra() {
        for notch in Self.notchWidths {
            for extra in Self.everyExtra {
                let expected = notch + 2 * 8 + 2 * (NotchClosedBodyLayout.wingWidth + extra)
                let g = NotchClosedBodyLayout.closedWingGeometry(notchWidth: notch, shoulder: 8, extra: extra)
                #expect(g.bodyWidth == expected)
                #expect(NotchClosedBodyLayout.bodyWidth(
                    notchWidth: notch, shoulder: 8, showWings: true, extraWidth: extra, hasNotch: true, slimPill: false) == expected)
            }
        }
    }

    @Test func aBarWithoutANotchKeepsAFortyPointGap() {
        for extra in Self.everyExtra {
            let width = NotchClosedBodyLayout.bodyWidth(
                notchWidth: 0, shoulder: 0, showWings: true, extraWidth: extra, hasNotch: false, slimPill: true)
            #expect(width == 40 + 2 * (NotchClosedBodyLayout.wingWidth + extra))
            let g = NotchClosedBodyLayout.closedWingGeometry(notchWidth: 40, shoulder: 0, extra: extra)
            #expect(g.bodyWidth == width)
            #expect(g.notchGap == -20 ... 20)
        }
    }

    @Test func theOldRightOnlyGrowthIsGone() {
        let g = NotchClosedBodyLayout.closedWingGeometry(notchWidth: 220, shoulder: 8, extra: 150)
        #expect(g.bodyWidth == 220 + 16 + 2 * (62 + 150))
        #expect(g.rightWing.lowerBound == 110)
    }
}
