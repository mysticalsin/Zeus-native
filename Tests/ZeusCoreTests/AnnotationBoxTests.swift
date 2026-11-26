import Foundation
import Testing
@testable import ZeusCore

@Suite struct AnnotationBoxTests {
    private func line() -> [AnnotationBox.Point] {
        (0...20).map { AnnotationBox.Point(x: 100 + Double($0) * 10, y: 300) }
    }

    private func circle() -> [AnnotationBox.Point] {
        (0...40).map { index in
            let angle = Double(index) / 40 * 2 * Double.pi
            return AnnotationBox.Point(x: 500 + 50 * cos(angle), y: 400 + 50 * sin(angle))
        }
    }

    private func scribble() -> [AnnotationBox.Point] {
        [
            AnnotationBox.Point(x: 0, y: 0),
            AnnotationBox.Point(x: 80, y: 40),
            AnnotationBox.Point(x: 0, y: 80),
            AnnotationBox.Point(x: 80, y: 120),
        ]
    }

    @Test func boundsCoverEverySample() {
        let rect = AnnotationBox.bounds(line())
        #expect(!rect.isNull)
        #expect(rect.x == 100)
        #expect(rect.y == 300)
        #expect(rect.width == 200)
        #expect(rect.height == 0)
    }

    @Test func anEmptyStrokeHasNoBoundsAndOneSampleIsAPoint() {
        #expect(AnnotationBox.bounds([]).isNull)
        let point = AnnotationBox.bounds([AnnotationBox.Point(x: 3, y: 4)])
        #expect(!point.isNull)
        #expect(point.x == 3)
        #expect(point.y == 4)
        #expect(point.width == 0)
        #expect(point.height == 0)
    }

    @Test func lengthIsTheSumOfTheSegments() {
        let right = [
            AnnotationBox.Point(x: 0, y: 0),
            AnnotationBox.Point(x: 3, y: 4),
        ]
        #expect(AnnotationBox.length(right) == 5)
        #expect(AnnotationBox.length(line()) == 200)
        #expect(AnnotationBox.length([]) == 0)
    }

    @Test func aShortStrokeOrTwoSamplesIsASpot() {
        let far = [AnnotationBox.Point(x: 0, y: 0), AnnotationBox.Point(x: 100, y: 0)]
        #expect(AnnotationBox.shape(far) == .spot)
        let tiny = [
            AnnotationBox.Point(x: 0, y: 0),
            AnnotationBox.Point(x: 4, y: 0),
            AnnotationBox.Point(x: 8, y: 0),
        ]
        #expect(AnnotationBox.shape(tiny) == .spot)
        #expect(AnnotationBox.shape(line()) == .line)
    }

    @Test func aStraightStrokeIsALine() {
        #expect(AnnotationBox.shape(line()) == .line)
        #expect(AnnotationBox.length(line()) == 200)
        let rect = AnnotationBox.bounds(line())
        #expect(rect.width == 200)
        #expect(rect.height == 0)
    }

    @Test func aClosedLoopIsACircle() {
        let loop = circle()
        #expect(AnnotationBox.shape(loop) == .circle)
        let rect = AnnotationBox.bounds(loop)
        #expect(abs(rect.x - 450) < 0.001)
        #expect(abs(rect.y - 350) < 0.001)
        #expect(abs(rect.width - 100) < 0.001)
        #expect(abs(rect.height - 100) < 0.001)
    }

    @Test func aBentStrokeIsAScribble() {
        #expect(AnnotationBox.shape(scribble()) == .scribble)
        let rect = AnnotationBox.bounds(scribble())
        #expect(rect.x == 0)
        #expect(rect.y == 0)
        #expect(rect.width == 80)
        #expect(rect.height == 120)
    }

    @Test func aLineBecomesABandAndASpotClampsToTheScreen() {
        let band = AnnotationBox.region(line(), screenMinX: 0, screenMinY: 0, screenWidth: 1000, screenHeight: 1000)
        #expect(!band.isNull)
        #expect(band.x == 88)
        #expect(band.y == 276)
        #expect(band.width == 224)
        #expect(band.height == 48)
        let tight = AnnotationBox.region(line(), screenMinX: 0, screenMinY: 0, screenWidth: 1000, screenHeight: 1000, padding: 0)
        #expect(tight.x == 100)
        #expect(tight.width == 200)
        #expect(tight.height == 48)
        let tap = [
            AnnotationBox.Point(x: 5, y: 5),
            AnnotationBox.Point(x: 6, y: 5),
        ]
        let clamped = AnnotationBox.region(tap, screenMinX: 0, screenMinY: 0, screenWidth: 1000, screenHeight: 1000)
        #expect(clamped.x == 0)
        #expect(clamped.y == 0)
        #expect(clamped.width == 46)
        #expect(clamped.height == 45)
    }

    @Test func aMarkOutsideTheScreenHasNoRegionAndOneInsideKeepsItsBand() {
        let away = [
            AnnotationBox.Point(x: 5000, y: 5000),
            AnnotationBox.Point(x: 5100, y: 5000),
            AnnotationBox.Point(x: 5200, y: 5000),
        ]
        #expect(AnnotationBox.region(away, screenMinX: 0, screenMinY: 0, screenWidth: 100, screenHeight: 100).isNull)
        let kept = AnnotationBox.region(line(), screenMinX: 0, screenMinY: 0, screenWidth: 1000, screenHeight: 1000)
        #expect(!kept.isNull)
        #expect(kept.height == 48)
    }

    @Test func pixelsFlipToTheTopLeftAndRound() {
        let flipped = AnnotationBox.pixelRect(
            minX: 100, maxY: 450, width: 100, height: 50,
            displayMinX: 0, displayMaxY: 500, displayWidth: 1000, displayHeight: 500,
            pixelWidth: 2000, pixelHeight: 1000)
        #expect(flipped.x == 200)
        #expect(flipped.y == 100)
        #expect(flipped.width == 200)
        #expect(flipped.height == 100)
        let rounded = AnnotationBox.pixelRect(
            minX: 1.5, maxY: 2, width: 1.5, height: 1,
            displayMinX: 0, displayMaxY: 10, displayWidth: 10, displayHeight: 10,
            pixelWidth: 10, pixelHeight: 10)
        #expect(rounded.x == 2)
        #expect(rounded.y == 8)
        #expect(rounded.width == 2)
        #expect(rounded.height == 1)
        let shifted = AnnotationBox.pixelRect(
            minX: 0, maxY: 10, width: 10, height: 10,
            displayMinX: -100, displayMaxY: 50, displayWidth: 200, displayHeight: 100,
            pixelWidth: 20, pixelHeight: 10)
        #expect(shifted.x == 10)
        #expect(shifted.y == 4)
        #expect(shifted.width == 1)
        #expect(shifted.height == 1)
    }
}
