import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Face selection")
struct FaceSelectionTests {
    private func box(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat? = nil) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height ?? width)
    }

    @Test func largestFaceWinsWithNoHistory() {
        let faces = [box(x: 0.1, y: 0.1, width: 0.2), box(x: 0.5, y: 0.3, width: 0.4), box(x: 0.2, y: 0.6, width: 0.3)]
        #expect(FaceSelection.select(in: faces, preferNear: nil) == 1)
        #expect(FaceSelection.select(in: [], preferNear: nil) == nil)
    }

    @Test func bystanderBelowTheWidthFloorIsIgnored() {
        let bystander = box(x: 0.7, y: 0.4, width: 0.17, height: 0.6)
        #expect(FaceSelection.select(in: [bystander], preferNear: nil) == nil)
        let owner = box(x: 0.3, y: 0.3, width: 0.2)
        #expect(FaceSelection.select(in: [bystander, owner], preferNear: nil) == 1)
        // The floor is inclusive.
        #expect(FaceSelection.select(in: [box(x: 0, y: 0, width: FaceSelection.minimumWidth)], preferNear: nil) == 0)
        // A bystander never wins by continuity either.
        #expect(FaceSelection.select(in: [bystander, owner], preferNear: bystander) == 1)
    }

    @Test func continuityBeatsALargerNewFace() {
        let previous = box(x: 0.1, y: 0.4, width: 0.25)
        let sameFace = box(x: 0.12, y: 0.4, width: 0.22)
        let biggerNewcomer = box(x: 0.6, y: 0.2, width: 0.4)
        #expect(FaceSelection.select(in: [biggerNewcomer, sameFace], preferNear: previous) == 1)
        #expect(FaceSelection.select(in: [biggerNewcomer, sameFace], preferNear: nil) == 0)
    }

    @Test func aPreviousFaceThatMovedAwayFallsBackToTheLargest() {
        let previous = box(x: 0.0, y: 0.0, width: 0.2)
        let far = box(x: 0.7, y: 0.7, width: 0.25)
        let farLarger = box(x: 0.6, y: 0.6, width: 0.3)
        #expect(FaceSelection.select(in: [far, farLarger], preferNear: previous) == 1)
    }

    @Test func tiesGoToTheFirstFace() {
        let a = box(x: 0.1, y: 0.1, width: 0.3)
        let b = box(x: 0.6, y: 0.1, width: 0.3)
        #expect(FaceSelection.select(in: [a, b], preferNear: nil) == 0)
        #expect(FaceSelection.largest(in: [a, b]) == 0)
    }

    @Test func largestIgnoresTheWidthFloorSoEnrollmentCanSayMoveCloser() {
        let small = box(x: 0.4, y: 0.4, width: 0.1)
        #expect(FaceSelection.select(in: [small], preferNear: nil) == nil)
        #expect(FaceSelection.largest(in: [small]) == 0)
        #expect(FaceSelection.largest(in: []) == nil)
    }

    @Test func malformedBoxesAreNeverPicked() {
        let broken = CGRect(x: CGFloat.nan, y: 0, width: CGFloat.nan, height: CGFloat.nan)
        let good = box(x: 0.3, y: 0.3, width: 0.3)
        #expect(FaceSelection.select(in: [broken], preferNear: nil) == nil)
        #expect(FaceSelection.select(in: [broken, good], preferNear: nil) == 1)
        #expect(FaceSelection.largest(in: [broken, good]) == 1)
        #expect(FaceSelection.select(in: [good], preferNear: broken) == 0)
    }

    @Test func imageSpaceFlipMatchesVision() {
        // Vision: normalized, origin at the bottom left. A box hugging the bottom edge lands at the bottom of the image.
        let size = CGSize(width: 640, height: 480)
        let bottom = FaceSelection.imageRect(fromNormalized: CGRect(x: 0.25, y: 0, width: 0.5, height: 0.25), imageSize: size)
        #expect(bottom == CGRect(x: 160, y: 360, width: 320, height: 120))
        let top = FaceSelection.imageRect(fromNormalized: CGRect(x: 0, y: 0.75, width: 0.5, height: 0.25), imageSize: size)
        #expect(top == CGRect(x: 0, y: 0, width: 320, height: 120))
        let whole = FaceSelection.imageRect(fromNormalized: CGRect(x: 0, y: 0, width: 1, height: 1), imageSize: size)
        #expect(whole == CGRect(x: 0, y: 0, width: 640, height: 480))
    }

    @Test func paddedCropStaysInsideTheImage() throws {
        let size = CGSize(width: 640, height: 480)
        let inner = try #require(FaceSelection.paddedCrop(CGRect(x: 200, y: 100, width: 100, height: 100), imageSize: size))
        #expect(inner == CGRect(x: 180, y: 80, width: 140, height: 140))
        let corner = try #require(FaceSelection.paddedCrop(CGRect(x: 0, y: 0, width: 100, height: 100), imageSize: size))
        #expect(corner == CGRect(x: 0, y: 0, width: 120, height: 120))
        let edge = try #require(FaceSelection.paddedCrop(CGRect(x: 560, y: 400, width: 100, height: 100), imageSize: size))
        #expect(CGRect(origin: .zero, size: size).contains(edge))
        #expect(edge.maxX == 640 && edge.maxY == 480)
        let fractional = try #require(FaceSelection.paddedCrop(CGRect(x: 10.4, y: 10.4, width: 50.3, height: 50.3), imageSize: size))
        #expect(CGRect(origin: .zero, size: size).contains(fractional))
        #expect(FaceSelection.paddedCrop(CGRect(x: 900, y: 900, width: 50, height: 50), imageSize: size) == nil)
        #expect(FaceSelection.paddedCrop(CGRect(x: 10, y: 10, width: 0, height: 0), imageSize: size) == nil)
        #expect(FaceSelection.paddedCrop(CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10), imageSize: size) == nil)
    }
}
