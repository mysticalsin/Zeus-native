import Foundation
import Testing
@testable import ZeusCore

@Suite("Drawn notch box")
struct DrawnNotchBoxTests {
    private func shape(_ width: Double, _ height: Double, _ offset: Double = 0) -> DrawnNotchShape {
        DrawnNotchShape(width: width, height: height, offset: offset)
    }

    /// The open panel with its ears, the same width `GlanceTopBar` contributes today.
    private let panelWidth = 925.0

    @Test func theNotchLabelIsDrawnAndBlankScalarsStayInTheLabel() {
        #expect(NotchlessStyle(label: "Notch") == .drawn)
        #expect(DrawnNotchBox.style(label: "Notch") == .drawn)
        // Exact scalars. These are not removed, so none of them is "Notch".
        // U+200B is a zero-width space. Linux `CharacterSet.whitespacesAndNewlines` treats it as blank.
        let blanks: [String] = [" ", "\t", "\n", "\r", "\u{200B}"]
        for blank in blanks {
            #expect(NotchlessStyle(label: "Notch" + blank) == .pill)
            #expect(NotchlessStyle(label: blank) == .pill)
            #expect(DrawnNotchBox.style(label: blank + "Notch") == .pill)
        }
        #expect(NotchlessStyle(label: "notch") == .pill)
        #expect(NotchlessStyle(label: "Pill") == .pill)
        #expect(NotchlessStyle(label: "") == .pill)
    }

    @Test func theLimitsAreTheSpecifiedRangesStepsAndDefaults() {
        #expect(DrawnNotchLimits.widthRange == 140...280)
        #expect(DrawnNotchLimits.widthStep == 5)
        #expect(DrawnNotchLimits.heightRange == 30...44)
        #expect(DrawnNotchLimits.heightStep == 1)
        #expect(DrawnNotchLimits.offsetRange == -400...400)
        #expect(DrawnNotchLimits.offsetStep == 5)
        #expect(DrawnNotchLimits.defaultShape == shape(185, 32))
        #expect(DrawnNotchBox.widthRange == DrawnNotchLimits.widthRange)
        #expect(DrawnNotchBox.defaultShape == DrawnNotchLimits.defaultShape)
    }

    @Test func aShapeOnTheStepStaysAndAHalfStepRoundsAwayFromZero() {
        #expect(DrawnNotchLimits.sanitized(shape(185, 32, 0)) == shape(185, 32, 0))
        #expect(DrawnNotchLimits.sanitized(shape(140, 30, -400)) == shape(140, 30, -400))
        #expect(DrawnNotchLimits.sanitized(shape(280, 44, 400)) == shape(280, 44, 400))
        #expect(DrawnNotchLimits.sanitized(shape(142.5, 30.5, -12.5)) == shape(145, 31, -15))
        #expect(DrawnNotchBox.sanitized(shape(187, 32.4, 7)) == shape(185, 32, 5))
    }

    @Test func valuesOutsideTheRangesClampAndANonFiniteFieldTakesItsDefault() {
        #expect(DrawnNotchLimits.sanitized(shape(10, 5, -5000)) == shape(140, 30, -400))
        #expect(DrawnNotchLimits.sanitized(shape(9000, 900, 5000)) == shape(280, 44, 400))
        #expect(DrawnNotchLimits.sanitized(shape(.nan, 40, 50)) == shape(185, 40, 50))
        #expect(DrawnNotchLimits.sanitized(shape(200, .infinity, 50)) == shape(200, 32, 50))
        #expect(DrawnNotchLimits.sanitized(shape(200, 40, -.infinity)) == shape(200, 40, 0))
        let once = DrawnNotchBox.sanitized(shape(.nan, 5, 9000))
        #expect(DrawnNotchBox.sanitized(once) == once)
    }

    @Test func aWideDisplayKeepsTheShapeAndAQuarterWidthSnapsDown() {
        #expect(DrawnNotchLimits.fitted(shape(280, 44, 400), screenWidth: 1920) == shape(280, 44, 400))
        #expect(DrawnNotchBox.fitted(shape(280, 32), screenWidth: 1024, panelWidth: panelWidth)?.width == 255)
        #expect(DrawnNotchBox.fitted(shape(185, 32), screenWidth: 600, panelWidth: panelWidth)?.width == 150)
        #expect(DrawnNotchLimits.fitted(shape(280, 32), screenWidth: 1280)?.width == 280)
    }

    @Test func theOffsetStaysInsideThePanelAndANarrowDisplayAllowsNone() {
        #expect(DrawnNotchBox.fitted(shape(185, 32, 400), screenWidth: 1280, panelWidth: panelWidth)?.offset == 165)
        #expect(DrawnNotchBox.fitted(shape(185, 32, -400), screenWidth: 1024, panelWidth: panelWidth)?.offset == -40)
        #expect(DrawnNotchLimits.fitted(shape(185, 32, 400), screenWidth: 700)?.offset == 0)
        #expect(DrawnNotchLimits.fitted(shape(185, 32, 35), screenWidth: 1280)?.offset == 35)
    }

    @Test func aDisplayThatCannotHoldTheNarrowestShapeIsNil() {
        #expect(DrawnNotchLimits.fitted(shape(185, 32), screenWidth: 559) == nil)
        #expect(DrawnNotchBox.fitted(shape(140, 30), screenWidth: 560, panelWidth: panelWidth) == shape(140, 30, 0))
        #expect(DrawnNotchLimits.fitted(shape(185, 32), screenWidth: 0) == nil)
        #expect(DrawnNotchLimits.fitted(shape(185, 32), screenWidth: -1920) == nil)
        for width in [Double.nan, Double.infinity, -Double.infinity] {
            #expect(DrawnNotchBox.fitted(shape(185, 32), screenWidth: width, panelWidth: panelWidth) == nil)
        }
        #expect(DrawnNotchLimits.fitted(shape(.nan, .infinity, 1e300), screenWidth: 1920) == shape(185, 32, 400))
    }

    @Test func thePublicFitUsesTheOpenPanelWidth() {
        let hostile = shape(187, 32.4, 7)
        #expect(DrawnNotchLimits.fitted(hostile, screenWidth: 1920) == shape(185, 32, 5))
        #expect(DrawnNotchLimits.fitted(hostile, screenWidth: 1024)
                == DrawnNotchBox.fitted(hostile, screenWidth: 1024, panelWidth: panelWidth))
        #expect(DrawnNotchBox.fitted(shape(185, 32, 400), screenWidth: 1280, panelWidth: 1400)?.offset == 0)
    }

    @Test func thePositionReadsCentreOrASnappedSideAndKeepsAZeroWidthSpace() {
        #expect(DrawnNotchLimits.positionText(0) == "Centre")
        #expect(DrawnNotchLimits.positionText(40) == "40 pt right")
        #expect(DrawnNotchLimits.positionText(-40) == "40 pt left")
        #expect(DrawnNotchLimits.positionText(41) == "40 pt right")
        #expect(DrawnNotchLimits.positionText(-2) == "Centre")
        #expect(DrawnNotchLimits.positionText(900) == "400 pt right")
        #expect(DrawnNotchLimits.positionText(.nan) == "Centre")
        #expect(DrawnNotchBox.positionText(400, unit: "points") == "400 points right")
        #expect(DrawnNotchBox.positionText(40, unit: "\u{200B}") == "40 \u{200B} right")
    }

    @Test func availabilityReadsConnectedBeforeTargetsAndTreatsANegativeAsNone() {
        #expect(DrawnNotchAvailability.resolve(targetsWithoutNotch: 0, connectedWithoutNotch: 0) == .noDisplay)
        #expect(DrawnNotchAvailability.resolve(targetsWithoutNotch: 1, connectedWithoutNotch: 0) == .noDisplay)
        #expect(DrawnNotchAvailability.resolve(targetsWithoutNotch: 0, connectedWithoutNotch: 2) == .notShown)
        #expect(DrawnNotchAvailability.resolve(targetsWithoutNotch: 2, connectedWithoutNotch: 1) == .ready)
        #expect(DrawnNotchBox.availability(targetsWithoutNotch: -3, connectedWithoutNotch: -1) == .noDisplay)
        #expect(DrawnNotchBox.availability(targetsWithoutNotch: -3, connectedWithoutNotch: 2) == .notShown)
    }

    @Test func beginSanitizesAndASecondBeginOrAnIdleEventChangesNothing() {
        let hostile = shape(.nan, 90, 7)
        let (adjusting, effects) = DrawnNotchCalibration.reduce(.idle, .begin(saved: hostile))
        #expect(adjusting == .adjusting(draft: shape(185, 44, 5), saved: shape(185, 44, 5)))
        #expect(effects.isEmpty)
        let (again, extra) = DrawnNotchBox.reduce(adjusting, .begin(saved: shape(140, 30)))
        #expect(again == adjusting)
        #expect(extra.isEmpty)
        let (idle, ignored) = DrawnNotchCalibration.reduce(.idle, .done)
        #expect(idle == .idle)
        #expect(ignored.isEmpty)
        #expect(DrawnNotchCalibration.shown(.idle, saved: shape(200, 36, 10)) == shape(200, 36, 10))
        #expect(!DrawnNotchCalibration.showsGuide(.idle))
        #expect(DrawnNotchCalibration.allowsOpen(.idle))
    }

    @Test func setsAndStepsSnapAndStopAtTheEnds() {
        let saved = shape(185, 32)
        var state = DrawnNotchCalibration.State.adjusting(draft: saved, saved: saved)
        state = DrawnNotchBox.reduce(state, .setWidth(187)).0
        state = DrawnNotchBox.reduce(state, .setHeight(32.6)).0
        state = DrawnNotchBox.reduce(state, .setOffset(-8)).0
        #expect(state == .adjusting(draft: shape(185, 33, -10), saved: saved))
        state = .adjusting(draft: shape(140, 30, -400), saved: saved)
        state = DrawnNotchCalibration.reduce(state, .step(.width, .down)).0
        state = DrawnNotchCalibration.reduce(state, .step(.height, .down)).0
        state = DrawnNotchCalibration.reduce(state, .step(.offset, .down)).0
        #expect(state == .adjusting(draft: shape(140, 30, -400), saved: saved))
        state = .adjusting(draft: shape(280, 44, 400), saved: saved)
        state = DrawnNotchBox.reduce(state, .step(.width, .up)).0
        state = DrawnNotchBox.reduce(state, .step(.height, .up)).0
        state = DrawnNotchBox.reduce(state, .step(.offset, .up)).0
        #expect(state == .adjusting(draft: shape(280, 44, 400), saved: saved))
        let (still, effects) = DrawnNotchCalibration.reduce(.idle, .step(.width, .up))
        #expect(still == .idle)
        #expect(effects.isEmpty)
    }

    @Test func resetRestoresTheDefaultAndDoneSavesOnlyAChange() {
        let saved = shape(200, 36, 40)
        let adjusting = DrawnNotchCalibration.State.adjusting(draft: shape(220, 40, 20), saved: saved)
        let (reset, resetEffects) = DrawnNotchBox.reduce(adjusting, .reset)
        #expect(reset == .adjusting(draft: shape(185, 32), saved: saved))
        #expect(resetEffects.isEmpty)
        let matching = DrawnNotchCalibration.State.adjusting(draft: saved, saved: saved)
        let (idle, effects) = DrawnNotchBox.reduce(matching, .done)
        #expect(idle == .idle)
        #expect(effects == [.announce(DrawnNotchCalibration.unchangedAnnouncement)])
        #expect(DrawnNotchCalibration.unchangedAnnouncement == "Notch shape unchanged")
        let (changed, _) = DrawnNotchBox.reduce(reset, .setWidth(190))
        let (done, savedEffects) = DrawnNotchCalibration.reduce(changed, .done)
        #expect(done == .idle)
        #expect(savedEffects == [.persist(shape(190, 32)), .announce(DrawnNotchCalibration.savedAnnouncement)])
        #expect(DrawnNotchCalibration.savedAnnouncement == "Notch shape saved")
    }

    @Test func cancelAndEverySurfaceLossDropTheDraftAndTheGuideFollowsThePhase() {
        let saved = shape(200, 36, 40)
        let adjusting = DrawnNotchCalibration.State.adjusting(draft: shape(220, 40, 20), saved: saved)
        let (cancelled, cancelEffects) = DrawnNotchCalibration.reduce(adjusting, .cancel)
        #expect(cancelled == .idle)
        #expect(cancelEffects.isEmpty)
        for loss in DrawnNotchCalibration.SurfaceLoss.allCases {
            let (next, effects) = DrawnNotchBox.reduce(adjusting, .surfaceGone(loss))
            #expect(next == .idle)
            #expect(effects.isEmpty)
        }
        #expect(DrawnNotchCalibration.shown(adjusting, saved: saved) == shape(220, 40, 20))
        #expect(DrawnNotchCalibration.showsGuide(adjusting))
        #expect(!DrawnNotchCalibration.allowsOpen(adjusting))
        #expect(DrawnNotchBox.shown(.idle, saved: saved) == saved)
    }
}
