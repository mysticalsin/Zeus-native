import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Drawn notch rules") struct DrawnNotchTests {
    private func shape(_ width: Double, _ height: Double, _ offset: Double = 0) -> DrawnNotchShape {
        DrawnNotchShape(width: width, height: height, offset: offset)
    }

    // MARK: Style label

    @Test func theNotchLabelIsTheDrawnStyleAndEverythingElseIsThePill() {
        #expect(NotchlessStyle(label: "Notch") == .drawn)
        #expect(NotchlessStyle(label: "Pill") == .pill)
        for label in ["", "notch", "NOTCH", "Notch ", "Slim", "pill", "\u{0}", "Nöt"] {
            #expect(NotchlessStyle(label: label) == .pill)
        }
    }

    // MARK: Limits

    @Test func theLimitsAreTheSpecifiedRangesStepsAndDefaults() {
        #expect(DrawnNotchLimits.widthRange == 140...280)
        #expect(DrawnNotchLimits.widthStep == 5)
        #expect(DrawnNotchLimits.heightRange == 30...44)
        #expect(DrawnNotchLimits.heightStep == 1)
        #expect(DrawnNotchLimits.offsetRange == -400...400)
        #expect(DrawnNotchLimits.offsetStep == 5)
        #expect(DrawnNotchLimits.defaultShape == shape(185, 32, 0))
    }

    @Test func theDefaultsEqualTheClosedNotchSize() {
        #expect(CGFloat(DrawnNotchLimits.defaultShape.width) == GlanceTopBar.closedSize.width)
        #expect(CGFloat(DrawnNotchLimits.defaultShape.height) == GlanceTopBar.closedSize.height)
    }

    @Test func aShapeInsideTheLimitsOnTheStepIsLeftAlone() {
        for item in [shape(185, 32, 0), shape(140, 30, -400), shape(280, 44, 400), shape(205, 37, 55)] {
            #expect(DrawnNotchLimits.sanitized(item) == item)
        }
    }

    @Test func valuesOffTheStepSnapToTheNearestStep() {
        #expect(DrawnNotchLimits.sanitized(shape(187, 32.4, 7)) == shape(185, 32, 5))
        #expect(DrawnNotchLimits.sanitized(shape(188, 32.6, -8)) == shape(190, 33, -10))
        #expect(DrawnNotchLimits.sanitized(shape(142.4, 35, 2.4)) == shape(140, 35, 0))
    }

    @Test func valuesOutsideTheRangesClampToTheEnds() {
        #expect(DrawnNotchLimits.sanitized(shape(10, 5, -5000)) == shape(140, 30, -400))
        #expect(DrawnNotchLimits.sanitized(shape(9000, 900, 5000)) == shape(280, 44, 400))
        #expect(DrawnNotchLimits.sanitized(shape(-185, -32, 0)) == shape(140, 30, 0))
        #expect(DrawnNotchLimits.sanitized(shape(Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, 0))
                == shape(280, 30, 0))
    }

    @Test func aNonFiniteFieldTakesItsDefaultAndTheOthersKeepTheirValue() {
        let defaults = DrawnNotchLimits.defaultShape
        #expect(DrawnNotchLimits.sanitized(shape(.nan, 40, 50)) == shape(defaults.width, 40, 50))
        #expect(DrawnNotchLimits.sanitized(shape(200, .infinity, 50)) == shape(200, defaults.height, 50))
        #expect(DrawnNotchLimits.sanitized(shape(200, 40, -.infinity)) == shape(200, 40, defaults.offset))
        #expect(DrawnNotchLimits.sanitized(shape(.nan, .nan, .nan)) == defaults)
    }

    @Test func sanitizingTwiceChangesNothing() {
        let inputs: [DrawnNotchShape] = [shape(187, 32.4, 7), shape(.nan, 5, 9000), shape(1e300, -1e300, 1e300), shape(0, 0, 0)]
        for item in inputs {
            let once = DrawnNotchLimits.sanitized(item)
            #expect(DrawnNotchLimits.sanitized(once) == once)
        }
    }

    // MARK: Fit to a display

    @Test func aWideDisplayKeepsTheShapeAndAllowsTheFullOffset() {
        #expect(DrawnNotchLimits.fitted(shape(280, 44, 400), screenWidth: 1920) == shape(280, 44, 400))
        #expect(DrawnNotchLimits.fitted(shape(185, 32, -400), screenWidth: 1920) == shape(185, 32, -400))
    }

    @Test func theWidthIsNeverMoreThanAQuarterOfTheDisplay() {
        // 1280 / 4 = 320: the 280 limit is the tighter one.
        #expect(DrawnNotchLimits.fitted(shape(280, 32), screenWidth: 1280)?.width == 280)
        // 1024 / 4 = 256, snapped down to 255.
        #expect(DrawnNotchLimits.fitted(shape(280, 32), screenWidth: 1024)?.width == 255)
        #expect(DrawnNotchLimits.fitted(shape(200, 32), screenWidth: 1024)?.width == 200)
        // 600 / 4 = 150.
        #expect(DrawnNotchLimits.fitted(shape(185, 32), screenWidth: 600)?.width == 150)
    }

    @Test func theOffsetStaysInsideThePanelWithItsEars() {
        // (1280 - 925) / 2 - 8 = 169.5, snapped toward zero to 165.
        #expect(DrawnNotchLimits.fitted(shape(185, 32, 400), screenWidth: 1280)?.offset == 165)
        #expect(DrawnNotchLimits.fitted(shape(185, 32, -400), screenWidth: 1280)?.offset == -165)
        // (1024 - 925) / 2 - 8 = 41.5, snapped to 40.
        #expect(DrawnNotchLimits.fitted(shape(185, 32, 400), screenWidth: 1024)?.offset == 40)
        #expect(DrawnNotchLimits.fitted(shape(185, 32, -400), screenWidth: 1024)?.offset == -40)
        // (1920 - 925) / 2 - 8 = 489.5: the 400 limit is the tighter one.
        #expect(DrawnNotchLimits.fitted(shape(185, 32, 400), screenWidth: 1920)?.offset == 400)
        #expect(DrawnNotchLimits.fitted(shape(185, 32, 35), screenWidth: 1280)?.offset == 35)
    }

    @Test func aDisplayNarrowerThanThePanelAllowsNoOffset() {
        // 700 holds the 925 pt panel in no way: the allowance is 0, never negative.
        #expect(DrawnNotchLimits.fitted(shape(185, 32, 400), screenWidth: 700)?.offset == 0)
        #expect(DrawnNotchLimits.fitted(shape(185, 32, -400), screenWidth: 700)?.offset == 0)
    }

    @Test func aDisplayTooNarrowForTheSmallestShapeGivesNil() {
        #expect(DrawnNotchLimits.fitted(shape(185, 32), screenWidth: 500) == nil)
        #expect(DrawnNotchLimits.fitted(shape(140, 30), screenWidth: 559) == nil)
        #expect(DrawnNotchLimits.fitted(shape(140, 30), screenWidth: 560) == shape(140, 30, 0))
        #expect(DrawnNotchLimits.fitted(shape(185, 32), screenWidth: 0) == nil)
        #expect(DrawnNotchLimits.fitted(shape(185, 32), screenWidth: -1920) == nil)
    }

    @Test func aNonFiniteDisplayWidthGivesNil() {
        for width in [Double.nan, .infinity, -.infinity] {
            #expect(DrawnNotchLimits.fitted(shape(185, 32), screenWidth: width) == nil)
        }
    }

    @Test func theFitSanitizesAHostileShapeFirst() {
        #expect(DrawnNotchLimits.fitted(shape(.nan, .infinity, 1e300), screenWidth: 1920)
                == shape(185, 32, 400))
        #expect(DrawnNotchLimits.fitted(shape(187, 32.4, 7), screenWidth: 1920) == shape(185, 32, 5))
    }

    @Test func aFittedShapeIsOnTheStepAndInsideEveryLimit() {
        for screen in [560.0, 700, 1024, 1280, 1512, 1920, 2560] {
            for item in [shape(140, 30, -400), shape(280, 44, 400), shape(185, 32, 0), shape(.nan, 31, 1e9)] {
                guard let fitted = DrawnNotchLimits.fitted(item, screenWidth: screen) else {
                    Issue.record("no fit on \(screen)")
                    continue
                }
                #expect(fitted.width <= screen / 4)
                #expect(DrawnNotchLimits.widthRange.contains(fitted.width))
                #expect(fitted.width.truncatingRemainder(dividingBy: 5) == 0)
                #expect(DrawnNotchLimits.heightRange.contains(fitted.height))
                #expect(abs(fitted.offset) <= max(0, (screen - 925) / 2 - 8))
                #expect(fitted.offset.truncatingRemainder(dividingBy: 5) == 0)
            }
        }
    }

    // MARK: Availability

    @Test func availabilityOverEveryCountPair() {
        let table: [(targets: Int, connected: Int, answer: DrawnNotchAvailability)] = [
            (0, 0, .noDisplay), (1, 0, .noDisplay), (2, 0, .noDisplay),
            (0, 1, .notShown), (0, 2, .notShown),
            (1, 1, .ready), (1, 2, .ready), (2, 1, .ready), (2, 2, .ready),
        ]
        for row in table {
            #expect(DrawnNotchAvailability.resolve(targetsWithoutNotch: row.targets, connectedWithoutNotch: row.connected) == row.answer)
        }
    }

    @Test func negativeCountsReadAsZero() {
        #expect(DrawnNotchAvailability.resolve(targetsWithoutNotch: -3, connectedWithoutNotch: -1) == .noDisplay)
        #expect(DrawnNotchAvailability.resolve(targetsWithoutNotch: -3, connectedWithoutNotch: 2) == .notShown)
        #expect(DrawnNotchAvailability.resolve(targetsWithoutNotch: 1, connectedWithoutNotch: -4) == .noDisplay)
    }

    // MARK: Position text

    @Test func thePositionReadsCentreOrADistanceLeftOrRight() {
        #expect(DrawnNotchLimits.positionText(0) == "Centre")
        #expect(DrawnNotchLimits.positionText(40) == "40 pt right")
        #expect(DrawnNotchLimits.positionText(-40) == "40 pt left")
        #expect(DrawnNotchLimits.positionText(5) == "5 pt right")
        #expect(DrawnNotchLimits.positionText(-400) == "400 pt left")
        #expect(DrawnNotchLimits.positionText(400, unit: "points") == "400 points right")
        #expect(DrawnNotchLimits.positionText(-35, unit: "points") == "35 points left")
        #expect(DrawnNotchLimits.positionText(0, unit: "points") == "Centre")
    }

    @Test func thePositionTextReadsTheSnappedValue() {
        #expect(DrawnNotchLimits.positionText(41) == "40 pt right")
        #expect(DrawnNotchLimits.positionText(-2) == "Centre")
        #expect(DrawnNotchLimits.positionText(900) == "400 pt right")
        #expect(DrawnNotchLimits.positionText(-900) == "400 pt left")
        for hostile in [Double.nan, .infinity, -.infinity] {
            #expect(DrawnNotchLimits.positionText(hostile) == "Centre")
        }
    }
}
