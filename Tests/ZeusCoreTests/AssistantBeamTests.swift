import Foundation
import Testing
@testable import ZeusCore

@Suite("Assistant beam geometry and motion")
struct AssistantBeamTests {
    @Test func sevenLobesAndBellContourStayAttachedToTheHostBottom() {
        let geometry = AssistantBeam.frame(elapsed: 3, level: 0.8, processing: false)
            .geometry(width: 360, height: 340)
        #expect(geometry.lobes.count == 7)
        #expect(geometry.lobes.map(\.colorIndex) == Array(0...6))
        #expect(geometry.band.count == 57)
        #expect(geometry.lobes.allSatisfy { $0.center.y == 340 })
        #expect(geometry.lobes.allSatisfy { $0.radiusX > 0 && $0.radiusY > 0 })
        #expect(geometry.band.contains { $0.y < 340 })
        #expect(geometry.band.allSatisfy { $0.y > 200 })
        #expect(zip(geometry.band, geometry.band.dropFirst()).allSatisfy { $0.x < $1.x })
    }

    @Test func processingUsesReferenceLegDurationCurveAndCentreStart() {
        #expect(abs(AssistantBeam.processingPosition(elapsed: 0)) < 1e-12)
        #expect(abs(AssistantBeam.processingPosition(elapsed: 0.55) - 1) < 1e-12)
        #expect(abs(AssistantBeam.processingPosition(elapsed: 1.65) + 1) < 1e-12)
        #expect(abs(AssistantBeam.processingPosition(elapsed: 2.2)) < 1e-12)
        // Halfway through the first outward half-leg: the 2.1 curve is visibly non-linear.
        let expected = 1 - pow(0.5, 2.1)
        #expect(abs(AssistantBeam.processingPosition(elapsed: 0.275) - expected) < 1e-12)
        for time in stride(from: 0.0, through: 12.0, by: 0.025) {
            #expect((-1...1).contains(AssistantBeam.processingPosition(elapsed: time)))
        }
    }

    @Test func processingGatherIsContinuousAndUsesItsOwnPhaseClock() {
        let onset = AssistantBeam.frame(elapsed: 100, level: 0, processing: true, processingElapsed: 0)
        let early = AssistantBeam.frame(elapsed: 100, level: 0, processing: true, processingElapsed: 0.3)
        let settled = AssistantBeam.frame(elapsed: 100, level: 0, processing: true, processingElapsed: 3)
        #expect(onset.gather == 0)
        #expect(early.gather > 0 && early.gather < settled.gather)
        #expect(settled.gather > 0.99)
        let amount = 1 - exp(-0.3 / (0.6 * 0.9))
        #expect(abs(early.gather - amount * amount * (3 - 2 * amount)) < 1e-12)
        let samePhase = AssistantBeam.frame(elapsed: 101, level: 0, processing: true, processingElapsed: 0.3)
        #expect(samePhase.gather == early.gather && samePhase.sweep == early.sweep)
        #expect(AssistantBeam.frame(elapsed: 3, level: 0, processing: false).gather == 0)
    }

    @Test func reducedMotionIsOneStaticFrameAcrossAudioAndPhaseChanges() {
        let still = AssistantBeam.frame(elapsed: 0, level: 0, processing: false, reduceMotion: true)
        for time in [0.0, 0.1, 2, 75, .infinity, .nan] {
            for level in [0.0, 0.2, 1, .nan] {
                let value = AssistantBeam.frame(elapsed: time, level: level, processing: true,
                                                processingElapsed: time, reduceMotion: true)
                #expect(value == still)
                #expect(value.geometry(width: 360, height: 340) == still.geometry(width: 360, height: 340))
            }
        }
        #expect(still.hueDegrees == 0 && still.gather == 0 && still.sweep == 0)
        #expect(still.geometry(width: 360, height: 340).glowOpacity > 0)
    }

    @Test func compactHostsScaleBeamLengthsWithoutScalingTheirLayout() {
        let frame = AssistantBeam.frame(elapsed: 2, level: 0.8, processing: false)
        let card = frame.geometry(width: 360, height: 340)
        let compact = frame.geometry(width: 360, height: 32, cornerRadius: 16)
        #expect(card.scale == 1)
        #expect(abs(compact.scale - 1.0 / 3) < 1e-12)
        #expect(compact.width == 360 && compact.height == 32)
        #expect(compact.lobes.allSatisfy { $0.center.y == 32 })
        for (full, small) in zip(card.lobes, compact.lobes) {
            #expect(abs(small.radiusY * 3 - full.radiusY) < 1e-10)
            #expect(abs(small.radiusX * 3 - full.radiusX) < 1e-10)
        }
        #expect(compact.band.map(\.y).min()! >= 0)
    }

    @Test func malformedInputNeverProducesNonfiniteDrawingCoordinates() {
        let values: [Double] = [-1, 0, 0.3, 1, .nan, .infinity, -.infinity, .greatestFiniteMagnitude]
        for value in values {
            let frame = AssistantBeam.frame(elapsed: value, level: value, processing: true, processingElapsed: value)
            #expect([frame.level, frame.gather, frame.sweep, frame.hueDegrees].allSatisfy { $0.isFinite })
            let geometry = frame.geometry(width: 360, height: 340, cornerRadius: value)
            #expect(geometry.band.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            #expect(geometry.lobes.allSatisfy {
                [$0.center.x, $0.center.y, $0.radiusX, $0.radiusY].allSatisfy(\.isFinite)
            })
            #expect((0...1).contains(geometry.glowOpacity))
            #expect((0...1).contains(geometry.bandOpacity))
            let malformed = frame.geometry(width: value, height: value, cornerRadius: value)
            #expect([malformed.width, malformed.height, malformed.scale, malformed.cornerRadius].allSatisfy { $0.isFinite })
        }
    }

    @Test func emptyOrInvalidHostDoesNotEmitDrawablePrimitives() {
        let frame = AssistantBeam.frame(elapsed: 2, level: 1, processing: true)
        for size: (Double, Double) in [(0, 340), (360, 0), (-1, 340), (.nan, 340), (360, .infinity)] {
            let geometry = frame.geometry(width: size.0, height: size.1)
            #expect(geometry.lobes.isEmpty && geometry.band.isEmpty)
            #expect(geometry.bandOpacity == 0 && geometry.glowOpacity == 0)
        }
    }

    @Test func louderInputRaisesTheLightWithoutChangingTheLobeIdentity() {
        let quiet = AssistantBeam.frame(elapsed: 2, level: 0, processing: false).geometry(width: 360, height: 340)
        let loud = AssistantBeam.frame(elapsed: 2, level: 1, processing: false).geometry(width: 360, height: 340)
        #expect(loud.glowOpacity > quiet.glowOpacity)
        #expect(loud.bandOpacity > quiet.bandOpacity)
        #expect(loud.lobes.map(\.radiusY).max()! > quiet.lobes.map(\.radiusY).max()!)
        #expect(loud.lobes.map(\.colorIndex) == quiet.lobes.map(\.colorIndex))
        #expect(loud.band.map(\.y).min()! < quiet.band.map(\.y).min()!)
    }

    @Test func lateSessionMeterChangesCannotRewriteAccumulatedLobeTravel() {
        // The former elapsed * currentDrive formula magnified a tiny meter delta by 22 hours.
        // A level change may resize the beam, but cannot move it several points in one frame.
        let time = 80_000.0
        let before = AssistantBeam.frame(elapsed: time, level: 0.2, processing: false)
            .geometry(width: 360, height: 340)
        let after = AssistantBeam.frame(elapsed: time, level: 0.200001, processing: false)
            .geometry(width: 360, height: 340)
        for (a, b) in zip(before.lobes, after.lobes) {
            #expect(abs(a.center.x - b.center.x) < 0.01)
            #expect(abs(a.radiusY - b.radiusY) < 0.01)
        }
    }
}
