import Foundation
import Testing
@testable import ZeusCore

@Suite("Face selection box")
struct FaceSelectionBoxTests {
    private func box(x: Double, y: Double, width: Double, height: Double? = nil) -> FaceSelectionBox.Rect {
        FaceSelectionBox.Rect(x: x, y: y, width: width, height: height ?? width)
    }

    private func size(_ width: Double, _ height: Double) -> FaceSelectionBox.Size {
        FaceSelectionBox.Size(width: width, height: height)
    }

    @Test func thresholdsMatchTheGlanceFloors() {
        #expect(FaceSelectionBox.minimumWidth == 0.18)
        #expect(FaceSelectionBox.continuityTolerance == 0.3)
        #expect(FaceSelectionBox.cropPadding == 0.2)
        let exact = box(x: 0, y: 0, width: FaceSelectionBox.minimumWidth)
        #expect(FaceSelectionBox.select(in: [exact], preferNear: nil) == 0)
    }

    @Test func largestFaceWinsWithNoHistory() {
        let faces = [box(x: 0.1, y: 0.1, width: 0.2), box(x: 0.5, y: 0.3, width: 0.4), box(x: 0.2, y: 0.6, width: 0.3)]
        #expect(FaceSelectionBox.select(in: faces, preferNear: nil) == 1)
        #expect(FaceSelectionBox.select(in: [], preferNear: nil) == nil)
    }

    @Test func bystanderBelowTheWidthFloorIsIgnored() {
        let bystander = box(x: 0.7, y: 0.4, width: 0.17, height: 0.6)
        #expect(FaceSelectionBox.select(in: [bystander], preferNear: nil) == nil)
        let owner = box(x: 0.3, y: 0.3, width: 0.2)
        #expect(FaceSelectionBox.select(in: [bystander, owner], preferNear: nil) == 1)
        #expect(FaceSelectionBox.select(in: [box(x: 0, y: 0, width: FaceSelectionBox.minimumWidth)], preferNear: nil) == 0)
        #expect(FaceSelectionBox.select(in: [bystander, owner], preferNear: bystander) == 1)
    }

    @Test func continuityBeatsALargerNewFace() {
        let previous = box(x: 0.1, y: 0.4, width: 0.25)
        let sameFace = box(x: 0.12, y: 0.4, width: 0.22)
        let biggerNewcomer = box(x: 0.6, y: 0.2, width: 0.4)
        #expect(FaceSelectionBox.select(in: [biggerNewcomer, sameFace], preferNear: previous) == 1)
        #expect(FaceSelectionBox.select(in: [biggerNewcomer, sameFace], preferNear: nil) == 0)
    }

    @Test func aPreviousFaceThatMovedAwayFallsBackToTheLargest() {
        let previous = box(x: 0, y: 0, width: 0.2)
        let far = box(x: 0.7, y: 0.7, width: 0.25)
        let farLarger = box(x: 0.6, y: 0.6, width: 0.3)
        #expect(FaceSelectionBox.select(in: [far, farLarger], preferNear: previous) == 1)
    }

    @Test func tiesKeepTheEarlierFace() {
        let a = box(x: 0.1, y: 0.1, width: 0.3)
        let b = box(x: 0.6, y: 0.1, width: 0.3)
        #expect(FaceSelectionBox.select(in: [a, b], preferNear: nil) == 0)
        #expect(FaceSelectionBox.largest(in: [a, b]) == 0)
        // Same distance from the previous centre. The later face is larger and still loses.
        let previous = box(x: 0, y: 0, width: 1)
        let earlier = box(x: 0.25, y: 0, width: 0.5)
        let later = box(x: 0, y: 0.5, width: 1, height: 0.5)
        #expect(FaceSelectionBox.select(in: [earlier, later], preferNear: previous) == 0)
        #expect(FaceSelectionBox.select(in: [earlier, later], preferNear: nil) == 1)
    }

    @Test func largestIgnoresTheWidthFloor() {
        let small = box(x: 0.4, y: 0.4, width: 0.1)
        #expect(FaceSelectionBox.select(in: [small], preferNear: nil) == nil)
        #expect(FaceSelectionBox.largest(in: [small]) == 0)
        #expect(FaceSelectionBox.largest(in: []) == nil)
    }

    @Test func malformedBoxesAreNeverPicked() {
        let broken = box(x: .nan, y: 0, width: .nan, height: .nan)
        let good = box(x: 0.3, y: 0.3, width: 0.3)
        #expect(FaceSelectionBox.select(in: [broken], preferNear: nil) == nil)
        #expect(FaceSelectionBox.select(in: [broken, good], preferNear: nil) == 1)
        #expect(FaceSelectionBox.largest(in: [broken, good]) == 1)
        #expect(FaceSelectionBox.select(in: [good], preferNear: broken) == 0)
        let flat = box(x: 0.2, y: 0.2, width: 0.4, height: 0)
        let negative = box(x: 0.2, y: 0.2, width: -0.4, height: 0.4)
        let infinite = box(x: .infinity, y: 0.2, width: 0.4)
        #expect(FaceSelectionBox.select(in: [flat, negative, infinite], preferNear: nil) == nil)
        #expect(FaceSelectionBox.largest(in: [flat, negative, infinite, good]) == 3)
    }

    @Test func imageSpaceFlipMatchesVision() {
        let image = size(640, 480)
        let bottom = FaceSelectionBox.imageRect(fromNormalized: box(x: 0.25, y: 0, width: 0.5, height: 0.25), imageSize: image)
        #expect(bottom == box(x: 160, y: 360, width: 320, height: 120))
        let top = FaceSelectionBox.imageRect(fromNormalized: box(x: 0, y: 0.75, width: 0.5, height: 0.25), imageSize: image)
        #expect(top == box(x: 0, y: 0, width: 320, height: 120))
        let whole = FaceSelectionBox.imageRect(fromNormalized: box(x: 0, y: 0, width: 1, height: 1), imageSize: image)
        #expect(whole == box(x: 0, y: 0, width: 640, height: 480))
    }

    @Test func paddedCropStaysInsideTheImage() {
        let image = size(640, 480)
        let inner = FaceSelectionBox.paddedCrop(box(x: 200, y: 100, width: 100, height: 100), imageSize: image)
        #expect(inner == box(x: 180, y: 80, width: 140, height: 140))
        let corner = FaceSelectionBox.paddedCrop(box(x: 0, y: 0, width: 100, height: 100), imageSize: image)
        #expect(corner == box(x: 0, y: 0, width: 120, height: 120))
        let edge = FaceSelectionBox.paddedCrop(box(x: 560, y: 400, width: 100, height: 100), imageSize: image)
        #expect(edge == box(x: 540, y: 380, width: 100, height: 100))
        let fractional = FaceSelectionBox.paddedCrop(box(x: 10.5, y: 20.5, width: 40, height: 30), imageSize: image, padding: 0.25)
        #expect(fractional == box(x: 0, y: 13, width: 61, height: 45))
        let hung = FaceSelectionBox.paddedCrop(box(x: -10.5, y: 10, width: 40, height: 20), imageSize: size(100, 100), padding: 0)
        #expect(hung == box(x: 0, y: 10, width: 30, height: 20))
        #expect(FaceSelectionBox.paddedCrop(box(x: 900, y: 900, width: 50, height: 50), imageSize: image) == nil)
        #expect(FaceSelectionBox.paddedCrop(box(x: 10, y: 10, width: 0, height: 0), imageSize: image) == nil)
        #expect(FaceSelectionBox.paddedCrop(box(x: .nan, y: 0, width: 10, height: 10), imageSize: image) == nil)
        #expect(FaceSelectionBox.paddedCrop(box(x: 10, y: 10, width: 10, height: 10), imageSize: size(.infinity, 10)) == nil)
        #expect(FaceSelectionBox.paddedCrop(box(x: 10, y: 10, width: 10, height: 10), imageSize: image, padding: .nan) == nil)
    }
}
