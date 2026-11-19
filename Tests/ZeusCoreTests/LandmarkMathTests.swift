import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Landmark math")
struct LandmarkMathTests {
    private func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-9) -> Bool { abs(a - b) <= tolerance }

    private func close(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 1e-9) -> Bool {
        close(a.x, b.x, tolerance) && close(a.y, b.y, tolerance)
    }

    @Test func similarityTransformMapsTheTemplateOntoItself() throws {
        let template = LandmarkMath.template
        let transform = try #require(LandmarkMath.similarityTransform(from: template, to: template))
        #expect(close(transform.a, 1) && close(transform.d, 1))
        #expect(close(transform.b, 0) && close(transform.c, 0))
        #expect(close(transform.tx, 0) && close(transform.ty, 0))
        for point in template { #expect(close(point.applying(transform), point)) }
    }

    @Test func similarityTransformRecoversRotationScaleAndShift() throws {
        let angle: CGFloat = .pi / 6
        let scale: CGFloat = 1.7
        let truth = CGAffineTransform(a: scale * cos(angle), b: scale * sin(angle),
                                      c: -scale * sin(angle), d: scale * cos(angle), tx: 40, ty: -12)
        let source = LandmarkMath.template
        let destination = source.map { $0.applying(truth) }
        let solved = try #require(LandmarkMath.similarityTransform(from: source, to: destination))
        #expect(close(solved.a, truth.a) && close(solved.b, truth.b))
        #expect(close(solved.c, truth.c) && close(solved.d, truth.d))
        #expect(close(solved.tx, truth.tx, 1e-6) && close(solved.ty, truth.ty, 1e-6))
        // The same fit from the two eyes alone, the fallback tier.
        let eyes = try #require(LandmarkMath.similarityTransform(from: Array(source.prefix(2)), to: Array(destination.prefix(2))))
        #expect(close(eyes.a, truth.a) && close(eyes.b, truth.b))
        #expect(close(eyes.tx, truth.tx, 1e-6) && close(eyes.ty, truth.ty, 1e-6))
    }

    @Test func degeneratePointsGiveNoTransform() {
        let template = LandmarkMath.template
        #expect(LandmarkMath.similarityTransform(from: [], to: []) == nil)
        #expect(LandmarkMath.similarityTransform(from: [template[0]], to: [template[1]]) == nil)
        #expect(LandmarkMath.similarityTransform(from: template, to: Array(template.dropLast())) == nil)
        let stacked = Array(repeating: CGPoint(x: 5, y: 5), count: 5)
        #expect(LandmarkMath.similarityTransform(from: stacked, to: template) == nil)
        var withNaN = template
        withNaN[2] = CGPoint(x: CGFloat.nan, y: 1)
        #expect(LandmarkMath.similarityTransform(from: withNaN, to: template) == nil)
        #expect(LandmarkMath.similarityTransform(from: template, to: withNaN) == nil)
        #expect(LandmarkMath.centroid([CGPoint(x: CGFloat.infinity, y: 0)]) == nil)
        #expect(LandmarkMath.centroid([]) == nil)
    }

    @Test func centroidIsTheMeanOfTheCorners() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 2), CGPoint(x: 0, y: 2)]
        #expect(LandmarkMath.centroid(square) == CGPoint(x: 2, y: 1))
    }

    @Test func eyeCenterPrefersThePupil() {
        let pupil = [CGPoint(x: 10, y: 10)]
        let outline = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 4), CGPoint(x: 0, y: 4)]
        #expect(LandmarkMath.eyeCenter(pupil: pupil, eye: outline) == CGPoint(x: 10, y: 10))
        #expect(LandmarkMath.eyeCenter(pupil: [], eye: outline) == CGPoint(x: 10, y: 2))
        #expect(LandmarkMath.eyeCenter(pupil: [CGPoint(x: CGFloat.nan, y: 0)], eye: outline) == CGPoint(x: 10, y: 2))
        #expect(LandmarkMath.eyeCenter(pupil: [], eye: []) == nil)
    }

    @Test func imageSpaceFlipMatchesVision() {
        // Vision gives pixels with the origin at the bottom left; the crop wants the top left.
        let flipped = LandmarkMath.flipVertical([CGPoint(x: 10, y: 0), CGPoint(x: 3, y: 480), CGPoint(x: 7, y: 120)],
                                                imageHeight: 480)
        #expect(flipped == [CGPoint(x: 10, y: 480), CGPoint(x: 3, y: 0), CGPoint(x: 7, y: 360)])
        #expect(LandmarkMath.flipVertical(flipped, imageHeight: 480) == [CGPoint(x: 10, y: 0), CGPoint(x: 3, y: 480), CGPoint(x: 7, y: 120)])
    }

    @Test func eyesAreOrderedByScreenPositionNotByLabel() {
        let left = CGPoint(x: 30, y: 50), right = CGPoint(x: 70, y: 52)
        #expect(LandmarkMath.twoPoints(eyeA: right, eyeB: left) == [left, right])
        #expect(LandmarkMath.twoPoints(eyeA: left, eyeB: right) == [left, right])
    }

    @Test func fivePointsPickTheMouthCornersFromTheLips() throws {
        let lips = [CGPoint(x: 44, y: 90), CGPoint(x: 50, y: 86), CGPoint(x: 62, y: 91), CGPoint(x: 56, y: 96)]
        let points = try #require(LandmarkMath.fivePoints(eyeA: CGPoint(x: 70, y: 40), eyeB: CGPoint(x: 30, y: 41),
                                                           nose: CGPoint(x: 50, y: 65), lips: lips))
        #expect(points.count == 5)
        #expect(points[0] == CGPoint(x: 30, y: 41) && points[1] == CGPoint(x: 70, y: 40))
        #expect(points[2] == CGPoint(x: 50, y: 65))
        #expect(points[3] == CGPoint(x: 44, y: 90) && points[4] == CGPoint(x: 62, y: 91))
        #expect(LandmarkMath.fivePoints(eyeA: .zero, eyeB: CGPoint(x: 1, y: 0), nose: .zero, lips: []) == nil)
    }

    @Test func medianTakesTheMiddleOrTheMeanOfTheMiddleTwo() {
        #expect(LandmarkMath.median([]) == 0)
        #expect(LandmarkMath.median([9, 1, 5]) == 5)
        #expect(LandmarkMath.median([4, 1, 2, 3]) == 2.5)
    }
}
