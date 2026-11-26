import Foundation
import Testing
@testable import ZeusCore

@Suite("LandmarkMathBox")
struct LandmarkMathBoxTests {
    private typealias Point = LandmarkMathBox.Point

    private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    @Test func templateIsTheAlignedCrop() {
        #expect(LandmarkMathBox.templateSize == 112)
        #expect(LandmarkMathBox.template == [
            Point(x: 38.2946, y: 51.6963),
            Point(x: 73.5318, y: 51.5014),
            Point(x: 56.0252, y: 71.7366),
            Point(x: 41.5493, y: 92.3655),
            Point(x: 70.7299, y: 92.2041),
        ])
        #expect(LandmarkMathBox.eyeTemplate == Array(LandmarkMathBox.template.prefix(2)))
    }

    @Test func similarityTransformMapsTheTemplateOntoItself() throws {
        let template = LandmarkMathBox.template
        #expect(template.count == 5)
        #expect(template[0] == Point(x: 38.2946, y: 51.6963))
        let transform = try #require(LandmarkMathBox.similarityTransform(from: template, to: template))
        #expect(close(transform.a, 1) && close(transform.d, 1))
        #expect(close(transform.b, 0) && close(transform.c, 0))
        #expect(close(transform.tx, 0) && close(transform.ty, 0))
    }

    @Test func similarityTransformRecoversRotationScaleAndShift() throws {
        let angle = Double.pi / 6
        let scale = 1.7
        let a = scale * cos(angle)
        let b = scale * sin(angle)
        let truth = LandmarkMathBox.Similarity(a: a, b: b, c: -b, d: a, tx: 40, ty: -12)
        let source = LandmarkMathBox.template
        let destination = source.map { point in
            Point(x: truth.a * point.x + truth.c * point.y + truth.tx,
                  y: truth.b * point.x + truth.d * point.y + truth.ty)
        }
        let solved = try #require(LandmarkMathBox.similarityTransform(from: source, to: destination))
        #expect(close(solved.a, truth.a) && close(solved.b, truth.b))
        #expect(close(solved.c, truth.c) && close(solved.d, truth.d))
        #expect(close(solved.tx, truth.tx, 1e-6) && close(solved.ty, truth.ty, 1e-6))
        let eyes = try #require(LandmarkMathBox.similarityTransform(from: Array(source.prefix(2)),
                                                                     to: Array(destination.prefix(2))))
        #expect(close(eyes.a, truth.a) && close(eyes.b, truth.b))
        #expect(close(eyes.tx, truth.tx, 1e-6) && close(eyes.ty, truth.ty, 1e-6))
    }

    @Test func degeneratePointsGiveNoTransform() {
        let template = LandmarkMathBox.template
        #expect(LandmarkMathBox.similarityTransform(from: [], to: []) == nil)
        #expect(LandmarkMathBox.similarityTransform(from: [template[0]], to: [template[1]]) == nil)
        #expect(LandmarkMathBox.similarityTransform(from: template, to: Array(template.dropLast())) == nil)
        let stacked = Array(repeating: Point(x: 5, y: 5), count: 5)
        #expect(LandmarkMathBox.similarityTransform(from: stacked, to: template) == nil)
        var withNaN = template
        withNaN[2] = Point(x: .nan, y: 1)
        #expect(LandmarkMathBox.similarityTransform(from: withNaN, to: template) == nil)
        #expect(LandmarkMathBox.similarityTransform(from: template, to: withNaN) == nil)
        #expect(LandmarkMathBox.centroid([Point(x: .infinity, y: 0)]) == nil)
        #expect(LandmarkMathBox.centroid([]) == nil)
    }

    @Test func centroidIsTheMeanOfTheCorners() {
        let square = [Point(x: 0, y: 0), Point(x: 4, y: 0), Point(x: 4, y: 2), Point(x: 0, y: 2)]
        #expect(LandmarkMathBox.centroid(square) == Point(x: 2, y: 1))
    }

    @Test func eyeCenterPrefersThePupil() {
        let pupil = [Point(x: 10, y: 10)]
        let outline = [Point(x: 0, y: 0), Point(x: 20, y: 0), Point(x: 20, y: 4), Point(x: 0, y: 4)]
        #expect(LandmarkMathBox.eyeCenter(pupil: pupil, eye: outline) == Point(x: 10, y: 10))
        #expect(LandmarkMathBox.eyeCenter(pupil: [], eye: outline) == Point(x: 10, y: 2))
        #expect(LandmarkMathBox.eyeCenter(pupil: [Point(x: .nan, y: 0)], eye: outline) == Point(x: 10, y: 2))
        #expect(LandmarkMathBox.eyeCenter(pupil: [], eye: []) == nil)
    }

    @Test func imageSpaceFlipMatchesABottomLeftOrigin() {
        let flipped = LandmarkMathBox.flipVertical([Point(x: 10, y: 0), Point(x: 3, y: 480), Point(x: 7, y: 120)],
                                                    imageHeight: 480)
        #expect(flipped == [Point(x: 10, y: 480), Point(x: 3, y: 0), Point(x: 7, y: 360)])
        #expect(LandmarkMathBox.flipVertical(flipped, imageHeight: 480) == [Point(x: 10, y: 0), Point(x: 3, y: 480), Point(x: 7, y: 120)])
    }

    @Test func eyesAreOrderedByScreenPosition() {
        let left = Point(x: 30, y: 50)
        let right = Point(x: 70, y: 52)
        #expect(LandmarkMathBox.twoPoints(eyeA: right, eyeB: left) == [left, right])
        #expect(LandmarkMathBox.twoPoints(eyeA: left, eyeB: right) == [left, right])
        let tied = Point(x: 5, y: 1)
        let other = Point(x: 5, y: 9)
        #expect(LandmarkMathBox.twoPoints(eyeA: tied, eyeB: other) == [tied, other])
    }

    @Test func fivePointsPickTheMouthCorners() throws {
        let lips = [Point(x: 44, y: 90), Point(x: 50, y: 86), Point(x: 62, y: 91), Point(x: 56, y: 96)]
        let points = try #require(LandmarkMathBox.fivePoints(eyeA: Point(x: 70, y: 40),
                                                              eyeB: Point(x: 30, y: 41),
                                                              nose: Point(x: 50, y: 65),
                                                              lips: lips))
        #expect(points == [
            Point(x: 30, y: 41),
            Point(x: 70, y: 40),
            Point(x: 50, y: 65),
            Point(x: 44, y: 90),
            Point(x: 62, y: 91),
        ])
        #expect(LandmarkMathBox.fivePoints(eyeA: Point(x: 0, y: 0), eyeB: Point(x: 1, y: 0),
                                            nose: Point(x: 0, y: 0), lips: []) == nil)
    }

    @Test func medianTakesTheMiddleOrTheMeanOfTheMiddleTwo() {
        #expect(LandmarkMathBox.median([]) == 0)
        #expect(LandmarkMathBox.median([9, 1, 5]) == 5)
        #expect(LandmarkMathBox.median([4, 1, 2, 3]) == 2.5)
    }
}
